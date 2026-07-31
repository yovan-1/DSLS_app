import 'package:dsls_app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const credentials = AwsCredentials(
    accessKey: 'AKIAIOSFODNN7EXAMPLE',
    secretKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
    bucketName: 'my-bucket',
    region: 'eu-west-1',
  );

  group('redaction', () {
    /// Without an explicit toString the default prints the instance, so a
    /// single stray debugPrint would put a long-lived IAM secret in the device
    /// log — where a crash reporter or a bug report would pick it up.
    test('toString never contains the secret', () {
      final text = credentials.toString();

      expect(text, isNot(contains(credentials.secretKey)));
      expect(text, contains('redacted'));
    });

    test('toString keeps enough to tell configurations apart', () {
      final text = credentials.toString();

      expect(text, contains('AKIA'));
      expect(text, contains('my-bucket'));
      expect(text, contains('eu-west-1'));
    });

    test('a short access key is not partially exposed', () {
      const short = AwsCredentials(accessKey: 'ab', secretKey: 'sh0rtS3cretV4l');

      expect(short.toString(), contains('****'));
      expect(short.toString(), isNot(contains('sh0rtS3cretV4l')));
      expect(short.toString(), isNot(contains('ab')));
    });

    /// toJson is what gets encrypted and stored, so it must keep the secret —
    /// the redaction belongs on the human-readable form only.
    test('toJson still carries the secret, since it is what gets stored', () {
      expect(credentials.toJson()['secretKey'], credentials.secretKey);
    });
  });

  group('defaults', () {
    test('come from one place', () {
      const minimal = AwsCredentials(accessKey: 'a', secretKey: 'b');

      expect(minimal.bucketName, AwsCredentials.defaultBucket);
      expect(minimal.region, AwsCredentials.defaultRegion);
    });

    test('fromJson falls back to them', () {
      final restored = AwsCredentials.fromJson({
        'accessKey': 'a',
        'secretKey': 'b',
      });

      expect(restored.bucketName, AwsCredentials.defaultBucket);
      expect(restored.region, AwsCredentials.defaultRegion);
    });

    /// The region was hardcoded in the save path, so a bucket outside
    /// us-east-1 could never be signed for correctly.
    test('a non-default region survives a round trip', () {
      final restored = AwsCredentials.fromJson(credentials.toJson());

      expect(restored.region, 'eu-west-1');
      expect(restored.bucketName, 'my-bucket');
      expect(restored.accessKey, credentials.accessKey);
      expect(restored.secretKey, credentials.secretKey);
    });
  });

  group('copyWith', () {
    test('changes only what it is given', () {
      final moved = credentials.copyWith(region: 'af-south-1');

      expect(moved.region, 'af-south-1');
      expect(moved.accessKey, credentials.accessKey);
      expect(moved.secretKey, credentials.secretKey);
      expect(moved.bucketName, credentials.bucketName);
    });
  });

  group('CredentialState', () {
    /// "Never configured" and "configured but unreadable" used to be the same
    /// null, so an upgrade that invalidated the stored blob left the user with
    /// a configured-looking form and uploads that silently never happened.
    test('distinguishes absent from unreadable', () {
      expect(CredentialState.values, contains(CredentialState.absent));
      expect(CredentialState.values, contains(CredentialState.present));
      expect(CredentialState.values, contains(CredentialState.unreadable));
      expect(CredentialState.absent, isNot(CredentialState.unreadable));
    });
  });
}
