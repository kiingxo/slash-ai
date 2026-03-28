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
      await init();
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

  static String? fetchString(String key) {
    try {
      return _prefs?.getString(key);
    } catch (e) {
      log("shared preference - $e");
      return null;
    }
  }

  static bool? fetchBool(String key) {
    try {
      return _prefs?.getBool(key);
    } catch (e) {
      log("shared preference - $e");
      return null;
    }
  }

  static int? fetchInt(String key) {
    try {
      return _prefs?.getInt(key);
    } catch (e) {
      log("shared preference - $e");
      return null;
    }
  }

  static double? fetchDouble(String key) {
    try {
      return _prefs?.getDouble(key);
    } catch (e) {
      log("shared preference - $e");
      return null;
    }
  }

  static Future<bool> remove(String key) async {
    try {
      if (_prefs == null) {
        return false;
      }
      return await _prefs!.remove(key);
    } catch (e) {
      throw Exception('unable to remove data.');
    }
  }

  static Future<void> clear() async {
    if (_prefs == null) {
      return;
    }
    await _prefs!.clear();
    log("cleared");
  }
}
