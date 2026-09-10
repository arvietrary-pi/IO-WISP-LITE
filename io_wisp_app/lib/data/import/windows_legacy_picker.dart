import 'package:flutter/services.dart';

import '../../domain/legacy_import.dart';

class WindowsLegacyFilePicker implements LegacyFilePicker {
  const WindowsLegacyFilePicker();
  static const channel = MethodChannel('io_wisp/legacy_import');
  @override
  Future<String?> selectJson() => channel.invokeMethod<String>('selectJson');
}
