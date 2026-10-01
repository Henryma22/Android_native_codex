import 'dart:io';

String getHomeDirectory() =>
    Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

bool get isDesktopPlatform =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;
bool get isMacOSPlatform => Platform.isMacOS;
bool get isIOSPlatform => Platform.isIOS;
bool get isAndroidPlatform => Platform.isAndroid;
String? getSystemLocaleName() => Platform.localeName;