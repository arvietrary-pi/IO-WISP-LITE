import 'package:flutter/services.dart';

import '../../domain/managed_file.dart';

class WindowsSourceFilePicker implements SourceFilePicker {
  const WindowsSourceFilePicker();
  @override
  Future<String?> selectSource() =>
      const MethodChannel('io_wisp/legacy_import')
          .invokeMethod<String>('selectSource');
}
