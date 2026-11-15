final Map<String, String> _memStore = {};

void saveStorageItem(String key, String? value) {
  if (value == null) {
    _memStore.remove(key);
  } else {
    _memStore[key] = value;
  }
}

String? readStorageItem(String key) {
  return _memStore[key];
}