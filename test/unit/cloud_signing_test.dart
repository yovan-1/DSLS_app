import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dsls_app/services/cloud_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The S3 client is a hand-rolled SigV4 implementation. Until now it had no
/// test of any kind, and every one of its failure modes — a wrong canonical
/// URI, a mis-ordered header, a bad signing-key chain — surfaces to the user as
/// an opaque 403 that looks exactly like "your credentials are wrong".
///
/// These pin the intermediate strings, not just the final header, because that
/// is what makes a break diagnosable.
void main() {
  // The credentials AWS uses throughout its own SigV4 documentation examples.
  const accessKey = 'AKIDEXAMPLE';
  const secretKey = 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY';
  final signingTime = DateTime.utc(2015, 8, 30, 12, 36, 0);

  SignedRequest signGet({
    String canonicalUri = '/',
    String host = 'example.amazonaws.com',
    String service = 'service',
    String region = 'us-east-1',
    Uint8List? payload,
  }) =>
      CloudUploadService.signRequest(
        method: 'GET',
        canonicalUri: canonicalUri,
        host: host,
        payload: payload ?? Uint8List(0),
        accessKey: accessKey,
        secretKey: secretKey,
        region: region,
        service: service,
        utcNow: signingTime,
      );

  group('the signing key chain', () {
    /// From AWS's "Examples of how to derive a signing key" page. If this is
    /// wrong nothing else can be right, and the error is invisible.
    test('matches the published derivation', () {
      List<int> hmac(List<int> key, String message) =>
          Hmac(sha256, key).convert(utf8.encode(message)).bytes;

      final kDate = hmac(utf8.encode('AWS4$secretKey'), '20150830');
      final kRegion = hmac(kDate, 'us-east-1');
      final kService = hmac(kRegion, 'iam');
      final kSigning = hmac(kService, 'aws4_request');

      final hex =
          kSigning.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      expect(
        hex,
        'c4afb1cc5771d871763a393e44b703571b55cc28424d1a5e86da6ed3c154a4b9',
      );
    });
  });

  group('canonical request', () {
    test('has the shape AWS specifies', () {
      final signed = signGet();
      final lines = signed.canonicalRequest.split('\n');

      expect(lines.first, 'GET');
      expect(lines[1], '/');
      expect(lines[2], '', reason: 'empty canonical query string');
      // Headers are lower-cased, sorted, and each terminated by a newline,
      // followed by a blank line before the signed-header list.
      expect(signed.canonicalRequest,
          contains('host:example.amazonaws.com\n'));
      expect(lines[lines.length - 2],
          'host;x-amz-content-sha256;x-amz-date');
      expect(lines.last, signed.payloadHash);
    });

    test('hashes an empty payload to the documented constant', () {
      expect(
        signGet().payloadHash,
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('signed headers are in ascending order', () {
      final signed = signGet();
      final header = RegExp(r'SignedHeaders=([^,]+)')
          .firstMatch(signed.authorization)!
          .group(1)!;
      final names = header.split(';');

      expect(names, List<String>.from(names)..sort(),
          reason: 'AWS rejects an out-of-order SignedHeaders list');
    });
  });

  group('string to sign', () {
    test('is the four documented lines', () {
      final signed = signGet();
      final lines = signed.stringToSign.split('\n');

      expect(lines, hasLength(4));
      expect(lines[0], 'AWS4-HMAC-SHA256');
      expect(lines[1], '20150830T123600Z');
      expect(lines[2], '20150830/us-east-1/service/aws4_request');
      // The fourth line is the hash of the canonical request.
      expect(
        lines[3],
        sha256.convert(utf8.encode(signed.canonicalRequest)).toString(),
      );
    });

    test('timestamps are the basic ISO 8601 forms AWS requires', () {
      final signed = signGet();

      expect(signed.amzDate, matches(RegExp(r'^\d{8}T\d{6}Z$')));
      expect(signed.amzDate, '20150830T123600Z');
    });
  });

  group('authorization header', () {
    test('carries the credential scope and a 64-hex signature', () {
      final signed = signGet();

      expect(signed.authorization, startsWith('AWS4-HMAC-SHA256 '));
      expect(
        signed.authorization,
        contains('Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request'),
      );
      expect(signed.signature, matches(RegExp(r'^[0-9a-f]{64}$')),
          reason: 'AWS requires lower-case hex');
    });

    test('is deterministic for identical inputs', () {
      expect(signGet().signature, signGet().signature);
    });

    test('changes when any signed input changes', () {
      final base = signGet().signature;

      expect(signGet(canonicalUri: '/other').signature, isNot(base));
      expect(signGet(host: 'other.amazonaws.com').signature, isNot(base));
      expect(signGet(region: 'eu-west-1').signature, isNot(base));
      expect(signGet(service: 's3').signature, isNot(base));
      expect(
        signGet(payload: Uint8List.fromList(utf8.encode('x'))).signature,
        isNot(base),
      );
    });

    /// The region was hardcoded to us-east-1 in the UI regardless of what the
    /// user stored, so a bucket anywhere else could never be signed for.
    test('the region reaches the credential scope', () {
      final signed = signGet(region: 'eu-west-1');

      expect(signed.authorization, contains('/eu-west-1/'));
      expect(signed.stringToSign, contains('/eu-west-1/'));
    });
  });

  group('object key encoding', () {
    /// AWS requires uppercase percent-encoding of everything outside the
    /// RFC 3986 unreserved set, with `/` preserved. Dart's own encoders do not
    /// match, which is why this is hand-rolled — and why it needs pinning.
    test('preserves the unreserved set and the path separator', () {
      expect(
        CloudUploadService.encodePathForTest('/trips/abc-123_x.y~z.json'),
        '/trips/abc-123_x.y~z.json',
      );
    });

    test('encodes a space as %20, not +', () {
      expect(
        CloudUploadService.encodePathForTest('/trips/my trip.json'),
        '/trips/my%20trip.json',
      );
    });

    test('uses uppercase hex', () {
      final encoded = CloudUploadService.encodePathForTest('/trips/a?b.json');

      expect(encoded, '/trips/a%3Fb.json');
      expect(encoded, isNot(contains('%3f')));
    });

    test('encodes characters Uri.encodeComponent leaves alone', () {
      // Uri.encodeComponent passes !*'() through untouched; AWS does not.
      // Tilde is genuinely unreserved and must survive.
      final encoded =
          CloudUploadService.encodePathForTest("/trips/a!b'c(d)~e.json");

      expect(encoded, contains('%21'));
      expect(encoded, contains('%27'));
      expect(encoded, contains('%28'));
      expect(encoded, contains('%29'));
      expect(encoded, contains('~'), reason: 'tilde is unreserved');
    });

    test('encodes multi-byte UTF-8 per byte', () {
      expect(
        CloudUploadService.encodePathForTest('/trips/é.json'),
        '/trips/%C3%A9.json',
      );
    });

    test('a signed request uses the encoded URI in the canonical request', () {
      final signed = CloudUploadService.signRequest(
        method: 'PUT',
        canonicalUri: CloudUploadService.encodePathForTest('/trips/a b.json'),
        host: 'bucket.s3.us-east-1.amazonaws.com',
        payload: Uint8List(0),
        accessKey: accessKey,
        secretKey: secretKey,
        region: 'us-east-1',
        utcNow: signingTime,
      );

      expect(signed.canonicalRequest, contains('/trips/a%20b.json'));
      expect(signed.canonicalRequest, isNot(contains('/trips/a b.json')));
    });
  });
}
