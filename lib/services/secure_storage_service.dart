import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  final _storage = const FlutterSecureStorage();

  Future<void> saveApiKey(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> getApiKey(String key) async {
    return await _storage.read(key: key);
  }

  Future<void> deleteApiKey(String key) async {
    await _storage.delete(key: key);
  }
} 