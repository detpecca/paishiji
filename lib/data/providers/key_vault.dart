// 拍食记 API Key 安全存储抽象。CLAUDE.md 红线#2：API Key 禁止明文进 SharedPreferences。
//
// 抽象两层：
// - KeyVault：存取两把 key（DashScope 必填、GLM 选填）
// - 测试用 MemoryKeyVault，生产用 SecureStorageKeyVault
//
// 这样 ConnectionTester / UI 全用抽象，测试零真实 secure_storage 插件依赖。
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:meta/meta.dart';

/// 哪把 key。
enum ApiKeyType { dashscope, glm }

/// API Key 存储抽象。
abstract class KeyVault {
  Future<String?> read(ApiKeyType which);
  Future<void> write(ApiKeyType which, String? value);
  Future<void> delete(ApiKeyType which);
  Future<Map<ApiKeyType, String>> readAll();
}

/// 生产实现：flutter_secure_storage（Android Keystore / iOS Keychain）。
class SecureStorageKeyVault implements KeyVault {
  SecureStorageKeyVault({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keys = {
    ApiKeyType.dashscope: 'paishiji.api.dashscope',
    ApiKeyType.glm: 'paishiji.api.glm',
  };

  @override
  Future<String?> read(ApiKeyType which) => _storage.read(key: _keys[which]!);

  @override
  Future<void> write(ApiKeyType which, String? value) {
    if (value == null || value.isEmpty) {
      return _storage.delete(key: _keys[which]!);
    }
    return _storage.write(key: _keys[which]!, value: value);
  }

  @override
  Future<void> delete(ApiKeyType which) => _storage.delete(key: _keys[which]!);

  @override
  Future<Map<ApiKeyType, String>> readAll() async {
    final dash = await read(ApiKeyType.dashscope);
    final glm = await read(ApiKeyType.glm);
    return {
      if (dash != null && dash.isNotEmpty) ApiKeyType.dashscope: dash,
      if (glm != null && glm.isNotEmpty) ApiKeyType.glm: glm,
    };
  }
}

/// 测试 / 离线实现：内存 Map，随用随弃。
@visibleForTesting
class MemoryKeyVault implements KeyVault {
  final Map<ApiKeyType, String> _store = {};

  @override
  Future<String?> read(ApiKeyType which) async => _store[which];

  @override
  Future<void> write(ApiKeyType which, String? value) async {
    if (value == null || value.isEmpty) {
      _store.remove(which);
    } else {
      _store[which] = value;
    }
  }

  @override
  Future<void> delete(ApiKeyType which) async => _store.remove(which);

  @override
  Future<Map<ApiKeyType, String>> readAll() async => Map.of(_store);
}
