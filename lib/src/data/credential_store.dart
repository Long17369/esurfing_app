import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 密码只进系统凭据库：
/// - Windows：DPAPI（flutter_secure_storage 的 win32 实现）；
/// - Android：Keystore + EncryptedSharedPreferences；
/// - macOS/iOS：Keychain（Apple 分支再启用）。
class CredentialStore {
  CredentialStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _key(String account) => 'esurfing.password.$account';

  Future<String?> read(String account) => _storage.read(key: _key(account));

  Future<void> write(String account, String password) =>
      _storage.write(key: _key(account), value: password);

  Future<void> delete(String account) => _storage.delete(key: _key(account));

  Future<Map<String, String>> readAll(Iterable<String> accounts) async {
    final result = <String, String>{};
    for (final account in accounts) {
      final value = await read(account);
      if (value != null && value.isNotEmpty) result[account] = value;
    }
    return result;
  }
}
