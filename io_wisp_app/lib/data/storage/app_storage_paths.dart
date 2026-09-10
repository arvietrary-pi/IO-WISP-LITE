import 'dart:io';

import 'package:path/path.dart' as p;

abstract class AppStoragePaths {
  String get databasePath;
  String get defaultProjectRoot;
}

class WindowsAppStoragePaths implements AppStoragePaths {
  WindowsAppStoragePaths({Map<String, String>? environment})
    : _environment = environment ?? Platform.environment;

  final Map<String, String> _environment;

  @override
  String get databasePath {
    return p.join(applicationSupportDirectory, 'io_wisp.sqlite');
  }

  @override
  String get defaultProjectRoot {
    final profile = _environment['USERPROFILE'];
    if (profile == null || profile.trim().isEmpty) {
      throw StateError('Windows user profile path is unavailable.');
    }
    return p.join(profile, 'Documents', 'IO WISP Projects');
  }

  String get applicationSupportDirectory {
    final appData = _environment['APPDATA'] ?? _environment['LOCALAPPDATA'];
    if (appData == null || appData.trim().isEmpty) {
      throw StateError('Windows application-data path is unavailable.');
    }
    return p.join(appData, 'IO WISP');
  }
}
