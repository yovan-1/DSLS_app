#!/usr/bin/env python3
"""Build the offline road database the app ships as an asset.

Pulls drivable ways for a bounding box from the OpenStreetMap Overpass API and
writes a SQLite file with an R-tree index over way bounding boxes.

Why Overpass rather than a Geofabrik .osm.pbf: a country extract is ~370 MB and
resolving node locations from it needs a multi-gigabyte cache, whereas Overpass
returns the same ways for a bounding box with geometry already inlined, in tens
of megabytes. Both are offline preprocessing — the *app* never talks to
Overpass, it only reads the SQLite file produced here.

Geometry is stored per way as a packed binary blob rather than one row per
node pair. The Mbarara box has ~14.8k ways but ~458k segments; storing ways
keeps the table small and the R-tree shallow, and the app refines a candidate
way by point-to-polyline distance anyway.

Usage:
    python3 tools/build_road_db.py --out assets/roads.db
    python3 tools/build_road_db.py --bbox -1.10 30.10 -0.10 31.20 --out assets/roads.db
    python3 tools/build_road_db.py --self-test
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import struct
import sys
import urllib.request
from datetime import datetime, timezone

SCHEMA_VERSION = 1

OVERPASS_URL = "https://overpass-api.de/api/interpreter"

# Drivable classes only. Tracks, paths and footways are excluded deliberately:
# a speed advisory has nothing useful to say about them.
HIGHWAY_CLASSES = [
    "motorway",
    "trunk",
    "primary",
    "secondary",
    "tertiary",
    "residential",
    "unclassified",
    "service",
    "living_street",
]

# OSM highway class -> the app's LocationType, by name.
LOCATION_TYPE = {
    "motorway": "highway",
    "trunk": "highway",
    "primary": "highway",
    "secondary": "suburban",
    "tertiary": "suburban",
    "residential": "residential",
    "unclassified": "residential",
    "service": "residential",
    "living_street": "residential",
}

# Fallback limit in km/h where `maxspeed` is absent. In this extract only 1.6%
# of ways carry the tag, so these govern almost everything and rows built from
# them are marked 'inferred' so the model applies its uncertainty margin.
#
# Uganda has no comprehensive posted-limit dataset; these follow the Traffic and
# Road Safety Act general limits, erring low where the class is ambiguous.
FALLBACK_LIMIT = {
    "motorway": 100,
    "trunk": 80,
    "primary": 80,
    "secondary": 60,
    "tertiary": 60,
    "residential": 40,
    "unclassified": 40,
    "service": 20,
    "living_street": 20,
}

# Default extract: Mbarara plus the trunk roads out of it.
DEFAULT_BBOX = (-1.10, 30.10, -0.10, 31.20)  # south, west, north, east


def build_query(bbox: tuple[float, float, float, float], timeout: int = 300) -> str:
    classes = "|".join(HIGHWAY_CLASSES)
    south, west, north, east = bbox
    return (
        f"[out:json][timeout:{timeout}];\n"
        f'way["highway"~"^({classes})$"]({south},{west},{north},{east});\n'
        f"out geom tags;\n"
    )


def fetch(query: str, url: str = OVERPASS_URL) -> dict:
    request = urllib.request.Request(
        url, data=query.encode("utf-8"), headers={"User-Agent": "dsls-road-db/1"}
    )
    with urllib.request.urlopen(request, timeout=600) as response:
        return json.loads(response.read().decode("utf-8"))


def parse_maxspeed(raw: str | None) -> int | None:
    """OSM `maxspeed` is free text. Returns km/h, or None if unusable.

    Handles the plain number, an explicit "N mph", and rejects everything else
    (`walk`, `none`, `signals`, country-code defaults) rather than guessing.
    """
    if not raw:
        return None
    value = raw.strip().lower()
    try:
        if value.endswith("mph"):
            return round(float(value[:-3].strip()) * 1.609344)
        if value.endswith("km/h") or value.endswith("kph"):
            value = value.replace("km/h", "").replace("kph", "").strip()
        return int(float(value))
    except ValueError:
        return None


def parse_lit(raw: str | None) -> int | None:
    """OSM `lit`. Returns 1, 0 or None for "not surveyed".

    The distinction matters: the speed model treats unknown lighting
    differently from known-unlit, and only 0.8% of ways here carry the tag.
    """
    if raw is None:
        return None
    value = raw.strip().lower()
    if value in ("yes", "24/7", "automatic", "sunset-sunrise", "dusk-dawn"):
        return 1
    if value in ("no", "disused"):
        return 0
    return None


def pack_geometry(points: list[tuple[float, float]]) -> bytes:
    """Little-endian float32 lat/lon pairs.

    float32 gives ~1 m of positional resolution at these latitudes, which is
    well inside GPS error and halves the size of the largest column.
    """
    out = bytearray()
    for lat, lon in points:
        out += struct.pack("<ff", lat, lon)
    return bytes(out)


def unpack_geometry(blob: bytes) -> list[tuple[float, float]]:
    count = len(blob) // 8
    return [struct.unpack_from("<ff", blob, i * 8) for i in range(count)]


SCHEMA = """
CREATE TABLE roads (
  id           INTEGER PRIMARY KEY,
  osm_way_id   INTEGER NOT NULL,
  name         TEXT,
  highway      TEXT NOT NULL,
  location_type TEXT NOT NULL,
  speed_limit  INTEGER NOT NULL,
  limit_source TEXT NOT NULL,
  lit          INTEGER,
  surface      TEXT,
  geometry     BLOB NOT NULL
);
CREATE VIRTUAL TABLE road_rtree USING rtree(
  id, min_lat, max_lat, min_lon, max_lon
);
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
"""


def build(elements: list[dict], out_path: str, bbox, source_note: str) -> dict:
    if os.path.exists(out_path):
        os.remove(out_path)

    db = sqlite3.connect(out_path)
    db.executescript(SCHEMA)

    stats = {"ways": 0, "posted": 0, "inferred": 0, "lit": 0, "surface": 0, "named": 0}
    road_id = 0

    for element in elements:
        geometry = element.get("geometry")
        if not geometry or len(geometry) < 2:
            continue
        tags = element.get("tags", {})
        highway = tags.get("highway")
        if highway not in LOCATION_TYPE:
            continue

        posted = parse_maxspeed(tags.get("maxspeed"))
        if posted is not None:
            speed_limit, limit_source = posted, "posted"
            stats["posted"] += 1
        else:
            speed_limit, limit_source = FALLBACK_LIMIT[highway], "inferred"
            stats["inferred"] += 1

        points = [(p["lat"], p["lon"]) for p in geometry]
        lats = [p[0] for p in points]
        lons = [p[1] for p in points]

        lit = parse_lit(tags.get("lit"))
        surface = tags.get("surface")
        name = tags.get("name")
        if lit is not None:
            stats["lit"] += 1
        if surface:
            stats["surface"] += 1
        if name:
            stats["named"] += 1

        road_id += 1
        db.execute(
            "INSERT INTO roads (id, osm_way_id, name, highway, location_type,"
            " speed_limit, limit_source, lit, surface, geometry)"
            " VALUES (?,?,?,?,?,?,?,?,?,?)",
            (
                road_id,
                element["id"],
                name,
                highway,
                LOCATION_TYPE[highway],
                speed_limit,
                limit_source,
                lit,
                surface,
                pack_geometry(points),
            ),
        )
        db.execute(
            "INSERT INTO road_rtree (id, min_lat, max_lat, min_lon, max_lon)"
            " VALUES (?,?,?,?,?)",
            (road_id, min(lats), max(lats), min(lons), max(lons)),
        )
        stats["ways"] += 1

    # Provenance. The hand-typed data this replaces carried none at all, so
    # nobody could tell how old it was or where it came from.
    meta = {
        "schema_version": str(SCHEMA_VERSION),
        "source": source_note,
        "license": "ODbL 1.0 (OpenStreetMap contributors)",
        "built_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "bbox": ",".join(str(v) for v in bbox),
        "highway_classes": ",".join(HIGHWAY_CLASSES),
        "fallback_limits": json.dumps(FALLBACK_LIMIT, sort_keys=True),
        "way_count": str(stats["ways"]),
        "posted_count": str(stats["posted"]),
        "inferred_count": str(stats["inferred"]),
    }
    db.executemany("INSERT INTO meta (key, value) VALUES (?,?)", meta.items())

    db.commit()
    db.execute("VACUUM")
    db.close()
    return stats


def self_test() -> int:
    """Exercises the tag parsing and the build, with no network."""
    assert parse_maxspeed("50") == 50
    assert parse_maxspeed(" 80 ") == 80
    assert parse_maxspeed("30 mph") == 48
    assert parse_maxspeed("60 km/h") == 60
    assert parse_maxspeed("none") is None
    assert parse_maxspeed("walk") is None
    assert parse_maxspeed(None) is None

    assert parse_lit("yes") == 1
    assert parse_lit("24/7") == 1
    assert parse_lit("no") == 0
    assert parse_lit("limited") is None
    assert parse_lit(None) is None

    packed = pack_geometry([(-0.6072, 30.6545), (-0.6, 30.65)])
    assert len(packed) == 16
    restored = unpack_geometry(packed)
    assert abs(restored[0][0] - (-0.6072)) < 1e-5
    assert abs(restored[1][1] - 30.65) < 1e-5

    elements = [
        {
            "id": 1,
            "tags": {"highway": "trunk", "maxspeed": "80", "lit": "yes", "name": "A"},
            "geometry": [{"lat": -0.61, "lon": 30.65}, {"lat": -0.59, "lon": 30.66}],
        },
        {
            "id": 2,
            "tags": {"highway": "residential"},
            "geometry": [{"lat": -0.60, "lon": 30.64}, {"lat": -0.60, "lon": 30.65}],
        },
        # Dropped: not a drivable class.
        {
            "id": 3,
            "tags": {"highway": "footway"},
            "geometry": [{"lat": -0.60, "lon": 30.64}, {"lat": -0.60, "lon": 30.65}],
        },
        # Dropped: needs at least two points to be a line.
        {"id": 4, "tags": {"highway": "primary"}, "geometry": [{"lat": 0, "lon": 30}]},
    ]

    tmp = "/tmp/_road_db_self_test.db"
    stats = build(elements, tmp, DEFAULT_BBOX, "self-test fixture")
    assert stats["ways"] == 2, stats
    assert stats["posted"] == 1, stats
    assert stats["inferred"] == 1, stats

    db = sqlite3.connect(tmp)
    rows = dict(
        (r[0], r) for r in db.execute(
            "SELECT osm_way_id, location_type, speed_limit, limit_source, lit FROM roads"
        )
    )
    assert rows[1][1] == "highway" and rows[1][2] == 80 and rows[1][3] == "posted"
    assert rows[2][1] == "residential" and rows[2][2] == 40 and rows[2][3] == "inferred"
    assert rows[2][4] is None, "an untagged lit must stay unknown, not become 0"

    # The R-tree must find the trunk way and not the residential one.
    hits = [
        r[0]
        for r in db.execute(
            "SELECT id FROM road_rtree WHERE max_lat >= ? AND min_lat <= ?"
            " AND max_lon >= ? AND min_lon <= ?",
            (-0.60, -0.60, 30.655, 30.655),
        )
    ]
    assert hits == [1], hits

    version = db.execute("SELECT value FROM meta WHERE key='schema_version'").fetchone()
    assert version[0] == str(SCHEMA_VERSION)
    db.close()
    os.remove(tmp)

    print("self-test OK")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="assets/roads.db")
    parser.add_argument(
        "--bbox",
        nargs=4,
        type=float,
        metavar=("SOUTH", "WEST", "NORTH", "EAST"),
        default=list(DEFAULT_BBOX),
    )
    parser.add_argument(
        "--cache",
        help="Read/write the raw Overpass JSON here, to avoid refetching.",
    )
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    bbox = tuple(args.bbox)

    if args.cache and os.path.exists(args.cache):
        print(f"reading cached Overpass response from {args.cache}")
        with open(args.cache) as handle:
            payload = json.load(handle)
        source_note = f"OpenStreetMap via Overpass (cached {args.cache})"
    else:
        query = build_query(bbox)
        print(f"querying Overpass for bbox {bbox} ...")
        payload = fetch(query)
        if args.cache:
            with open(args.cache, "w") as handle:
                json.dump(payload, handle)
        source_note = "OpenStreetMap via Overpass API"

    elements = payload.get("elements", [])
    print(f"received {len(elements)} ways")

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    stats = build(elements, args.out, bbox, source_note)

    # A tiny companion asset the app reads at startup to decide whether the
    # copy in its documents directory is stale. Cheaper than hashing 5 MB.
    db = sqlite3.connect(args.out)
    built = db.execute("SELECT value FROM meta WHERE key='built_utc'").fetchone()[0]
    db.close()
    with open(args.out + ".version", "w") as handle:
        handle.write(f"{SCHEMA_VERSION}:{built}\n")

    size_mb = os.path.getsize(args.out) / (1024 * 1024)
    total = max(stats["ways"], 1)
    print(f"wrote {args.out}  ({size_mb:.1f} MB)")
    print(f"  ways:     {stats['ways']}")
    print(f"  posted:   {stats['posted']} ({100 * stats['posted'] / total:.1f}%)")
    print(f"  inferred: {stats['inferred']} ({100 * stats['inferred'] / total:.1f}%)")
    print(f"  lit:      {stats['lit']} ({100 * stats['lit'] / total:.1f}%)")
    print(f"  surface:  {stats['surface']} ({100 * stats['surface'] / total:.1f}%)")
    print(f"  named:    {stats['named']} ({100 * stats['named'] / total:.1f}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
