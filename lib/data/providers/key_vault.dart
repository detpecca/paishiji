// 拍食记 API Key 安全存储抽象。CLAUDE.md 红线#2：API Key 禁止明文进 SharedPreferences。
//
// 抽象两层：
// - KeyVault：存取三把 key（DashScope 必填、GLM 选填、自定义 OpenAI 兼容端点选填）
// - 测试用 MemoryKeyVault，生产用 SecureStorageKeyVault
//
// 自定义配置（baseUrl + model + apiKey 三字段）以 JSON 字符串存入 custom 这一档 key。
//
// 这样 ConnectionTester / UI 全用抽象，测试零真实 secure_storage 插件依赖。
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:meta/meta.dart';

/// 哪把 key。
enum ApiKeyType { dashscope, glm, custom }

/// 自定义 OpenAI 兼容 provider 的三字段配置。
/// 存储时序列化为 JSON 字符串塞进 ApiKeyType.custom 这一档 key。
class CustomProviderConfig {
  const CustomProviderConfig({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  final String baseUrl;
  final String model;
  final String apiKey;

  /// 三字段都非空才算完整，才会被接入降级链。
  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'model': model,
    'apiKey': apiKey,
  };

  String toJsonString() => jsonEncode(toJson());

  /// 不合法 / null / 缺字段 → null。
  static CustomProviderConfig? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final baseUrl = decoded['baseUrl'];
      final model = decoded['model'];
      final apiKey = decoded['apiKey'];
      if (baseUrl is! String || model is! String || apiKey is! String) {
        return null;
      }
      return CustomProviderConfig(
        baseUrl: baseUrl,
        model: model,
        apiKey: apiKey,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'CustomProviderConfig($baseUrl, $model, ***)';
}

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
    ApiKeyType.custom: 'paishiji.api.custom',
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
  Future<void> delete(ApiKeyType which) =>
      _storage.delete(key: _keys[which]!);

  @override
  Future<Map<ApiKeyType, String>> readAll() async {
    final dash = await read(ApiKeyType.dashscope);
    final glm = await read(ApiKeyType.glm);
    final custom = await read(ApiKeyType.custom);
    return {
      if (dash != null && dash.isNotEmpty) ApiKeyType.dashscope: dash,
      if (glm != null && glm.isNotEmpty) ApiKeyType.glm: glm,
      if (custom != null && custom.isNotEmpty) ApiKeyType.custom: custom,
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
