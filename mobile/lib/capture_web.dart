class Capture {
  static Future<void> setSession({required String token, required String baseUrl}) async {}

  static Future<void> clearSession() async {}

  static Future<bool> notificationAccessEnabled() async => false;

  static Future<void> openNotificationAccess() async {}

  static Future<bool> smsPermissionGranted() async => false;

  static Future<void> requestSmsPermission() async {}

  static Future<bool> autoTrackEnabled() async => false;

  static Future<void> setAutoTrack(bool enabled) async {}

  static Future<bool> openMessageShortcut() async => false;

  static Future<String?> takeSharedText() async => null;
}

String defaultApiBase() => 'https://api.takings.alphabet.lk';

bool get isAndroidPhone => false;

bool get isIosPhone => false;
