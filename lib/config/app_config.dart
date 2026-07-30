/// Project-wide constants that must not be duplicated across screens.
class AppConfig {
  const AppConfig._();

  /// Address that Contact Us and Feedback send to.
  ///
  /// Keep this a project/team address, not an individual's personal mailbox —
  /// it ships inside every APK and outlives whoever set it up.
  static const String contactEmail = 'dsls.project@gmail.com';

  /// Identifies the app to the OpenStreetMap tile servers. Their usage policy
  /// requires a genuine, contactable identifier; the Flutter template default
  /// (`com.example.*`) is explicitly disallowed.
  static const String osmUserAgent = 'com.dsls.app';
}
