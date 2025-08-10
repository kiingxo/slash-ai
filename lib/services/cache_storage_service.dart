import 'dart:developer';

import 'package:shared_preferences/shared_preferences.dart';

class CacheStorage {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    log('SharedPreference Initialized');
  }


static Future<void> save(String key, Object? value) async {
  if (_prefs == null) {
    log('SharedPreferences not initialized.');
    return;
  }

  try {
    if (value is String) {
      await _prefs!.setString(key, value);
    } else if (value is int) {
      await _prefs!.setInt(key, value);
    } else if (value is double) {
      await _prefs!.setDouble(key, value);
    } else if (value is bool) {
      await _prefs!.setBool(key, value);
    } else if (value is List<String>) {
      await _prefs!.setStringList(key, value);
    } else {
      log('Unsupported cache value type: ${value.runtimeType}');
    }
  } catch (e, stack) {
    log('Unable to cache data for key "$key": $e\n$stack');
  }
}
  static dynamic fetchString(String key) {
    try {
      return _prefs!.getString(key);
    } catch (e) {
      log("shared preference - $e");
    }
  }

  static dynamic fetchBool(String key) {
    try {
      return _prefs!.getBool(key);
    } catch (e) {
      log("shared preference - $e");
    }
  }

  static dynamic fetchInt(String key) {
    try {
      return _prefs!.getInt(key);
    } catch (e) {
      log("shared preference - $e");
    }
  }

  static dynamic fetchDouble(String key) {
    try {
      return _prefs!.getDouble(key);
    } catch (e) {
      log("shared preference - $e");
    }
  }

  static dynamic remove(String key) {
    try {
      return _prefs!.remove(key);
    } catch (e) {
      throw Exception('unable to remove data.');
    }
  }

  static clear() {
    _prefs!.clear();
    log("cleared");
  }
}
