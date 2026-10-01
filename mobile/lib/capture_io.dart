import 'dart:io';

import 'package:flutter/services.dart';

import 'api_config.dart';

const _channel = MethodChannel('com.folio/capture');

class Capture {
  static Future<void> setSession({required String token, required String baseUrl}) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('setSession', {'token': token, 'baseUrl': baseUrl});
  }

  static Future<void> clearSession() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('clearSession');
  }

  static Future<bool> notificationAccessEnabled() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('notificationAccessEnabled') ?? false;
  }

  static Future<void> openNotificationAccess() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('openNotificationAccess');
  }

  static Future<bool> smsPermissionGranted() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('smsPermissionGranted') ?? false;
  }

  static Future<void> requestSmsPermission() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('requestSmsPermission');
  }

  static Future<bool> autoTrackEnabled() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('autoTrackEnabled') ?? true;
  }

  static Future<void> setAutoTrack(bool enabled) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('setAutoTrack', {'enabled': enabled});
  }

  static Future<bool> openMessageShortcut() async {
    if (!Platform.isIOS) return false;
    return await _channel.invokeMethod<bool>('openMessageShortcut') ?? false;
  }

  static Future<String?> takeSharedText() async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('takeSharedText');
  }
}

String defaultApiBase() => ApiConfig.baseUrl;

bool get isAndroidPhone => Platform.isAndroid;

bool get isIosPhone => Platform.isIOS;
