import 'dart:convert';
import 'dart:io';

final Map<String, String> _memFallback = {};

File? _resolveStoreFile() {
  try {
    final baseDir = Platform.isAndroid
        ? Directory('${Directory.systemTemp.parent.path}/files')
        : Directory('${Directory.systemTemp.path}/verilens_store');
    if (!baseDir.existsSync()) {
      baseDir.createSync(recursive: true);
    }
    return File('${baseDir.path}/verilens_store.json');
  } catch (_) {
    try {
      return File('${Directory.systemTemp.path}/verilens_store.json');
    } catch (_) {
      return null;
    }
  }
}

Map<String, String> _readDiskMap() {
  try {
    final file = _resolveStoreFile();
    if (file != null && file.existsSync()) {
      final raw = file.readAsStringSync();
      if (raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      }
    }
  } catch (_) {}
  return Map<String, String>.from(_memFallback);
}

void saveStorageItem(String key, String? value) {
  if (value == null) {
    _memFallback.remove(key);
  } else {
    _memFallback[key] = value;
  }
  try {
    final map = _readDiskMap();
    if (value == null) {
      map.remove(key);
    } else {
      map[key] = value;
    }
    final file = _resolveStoreFile();
    if (file != null) {
      file.writeAsStringSync(jsonEncode(map));
    }
  } catch (_) {}
}

String? readStorageItem(String key) {
  if (_memFallback.containsKey(key)) {
    return _memFallback[key];
  }
  final map = _readDiskMap();
  final val = map[key];
  if (val != null) {
    _memFallback[key] = val;
  }
  return val;
}