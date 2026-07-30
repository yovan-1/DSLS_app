import 'package:flutter_test/flutter_test.dart';
import 'package:dsls_app/models/speed_model/solar_position.dart';

void main() {
  // Mbarara, Uganda — where the project's road data is.
  const mbararaLat = -0.6072;
  const mbararaLon = 30.6545;

  /// Scans a day in one-minute steps and returns the UTC minute-of-day at which
  /// elevation peaks. Deriving this beats hardcoding a time, because solar noon
  /// depends on longitude and the equation of time.
  int solarNoonMinuteUtc(DateTime day, double lat, double lon) {
    var bestMinute = 0;
    var bestElevation = -90.0;
    for (var minute = 0; minute < 24 * 60; minute++) {
      final elevation = SolarPosition.elevationDegrees(
        utc: day.add(Duration(minutes: minute)),
        latitude: lat,
        longitude: lon,
      );
      if (elevation > bestElevation) {
        bestElevation = elevation;
        bestMinute = minute;
      }
    }
    return bestMinute;
  }

  group('elevationDegrees', () {
    test('sun passes nearly overhead at solar noon in Mbarara', () {
      // Mbarara sits almost on the equator, so at the equinox the sun is very
      // close to the zenith at solar noon.
      final day = DateTime.utc(2026, 3, 21);
      final noon = solarNoonMinuteUtc(day, mbararaLat, mbararaLon);

      final elevation = SolarPosition.elevationDegrees(
        utc: day.add(Duration(minutes: noon)),
        latitude: mbararaLat,
        longitude: mbararaLon,
      );

      expect(elevation, greaterThan(85));
      // Longitude 30.65°E puts solar noon around 10:00 UTC.
      expect(noon, inInclusiveRange(9 * 60 + 30, 10 * 60 + 30));
    });

    test('sun is well below the horizon 12 hours from solar noon', () {
      final day = DateTime.utc(2026, 3, 21);
      final noon = solarNoonMinuteUtc(day, mbararaLat, mbararaLon);

      final elevation = SolarPosition.elevationDegrees(
        utc: day.add(Duration(minutes: noon + 12 * 60)),
        latitude: mbararaLat,
        longitude: mbararaLon,
      );

      expect(elevation, lessThan(-80));
    });

    test('equinox day near the equator is about 12 hours long', () {
      final day = DateTime.utc(2026, 3, 21);
      var daylightMinutes = 0;
      for (var minute = 0; minute < 24 * 60; minute++) {
        final elevation = SolarPosition.elevationDegrees(
          utc: day.add(Duration(minutes: minute)),
          latitude: mbararaLat,
          longitude: mbararaLon,
        );
        if (elevation > 0) daylightMinutes++;
      }

      expect(daylightMinutes, closeTo(12 * 60, 20));
    });

    test('polar winter keeps the sun below the horizon all day', () {
      // Tromsø in December — a sanity check that the algorithm behaves at high
      // latitudes, not just near the equator.
      for (var hour = 0; hour < 24; hour++) {
        final elevation = SolarPosition.elevationDegrees(
          utc: DateTime.utc(2025, 12, 21, hour),
          latitude: 69.65,
          longitude: 18.96,
        );
        expect(elevation, lessThan(0), reason: 'hour $hour');
      }
    });
  });

  group('stateForElevation', () {
    test('bands elevation into daylight states', () {
      expect(SolarPosition.stateForElevation(45), DaylightState.daylight);
      expect(SolarPosition.stateForElevation(6.1), DaylightState.daylight);
      expect(SolarPosition.stateForElevation(3), DaylightState.lowSun);
      expect(SolarPosition.stateForElevation(0.1), DaylightState.lowSun);
      expect(SolarPosition.stateForElevation(-3), DaylightState.twilight);
      expect(SolarPosition.stateForElevation(-6.1), DaylightState.night);
      expect(SolarPosition.stateForElevation(-40), DaylightState.night);
    });
  });

  group('stateFor', () {
    test('reports night in Mbarara at local midnight', () {
      expect(
        SolarPosition.stateFor(
          utc: DateTime.utc(2026, 3, 21, 22),
          latitude: mbararaLat,
          longitude: mbararaLon,
        ),
        DaylightState.night,
      );
    });

    test('reports daylight in Mbarara at local noon', () {
      expect(
        SolarPosition.stateFor(
          utc: DateTime.utc(2026, 3, 21, 10),
          latitude: mbararaLat,
          longitude: mbararaLon,
        ),
        DaylightState.daylight,
      );
    });

    test('distinguishes summer from winter evenings at high latitude', () {
      // The case clock-hour buckets get wrong: 21:00 local is broad daylight in
      // a Nordic summer and pitch dark in winter.
      const oslolat = 59.91;
      const osloLon = 10.75;

      final summer = SolarPosition.stateFor(
        utc: DateTime.utc(2026, 6, 21, 19), // 21:00 local (UTC+2)
        latitude: oslolat,
        longitude: osloLon,
      );
      final winter = SolarPosition.stateFor(
        utc: DateTime.utc(2026, 12, 21, 20), // 21:00 local (UTC+1)
        latitude: oslolat,
        longitude: osloLon,
      );

      expect(summer, isNot(DaylightState.night));
      expect(winter, DaylightState.night);
    });
  });
}
