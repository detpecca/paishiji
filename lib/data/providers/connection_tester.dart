// 拍食记 API Key 连通性验证。CLAUDE.md §六 Task 3 DoD：错误 key 提示"密钥无效"。
//
// 抽象 ConnectionTester：
// - HttpConnectionTester：生产，用 dio 发"最小请求"（文本 ping，不耗图片额度）
// - MockConnectionTester：测试，按 key 内容判定，零真实 API 调用（红线#2）
//
// 走公司代理 env（HTTP_PROXY）—— dio 默认读系统代理，无需额外配置。
import 'package:dio/dio.dart';
import 'package:meta/meta.dart';

import '../../core/constants.dart';
import 'key_vault.dart';

/// 测试连接结果。UI 据此展示"有效 / 密钥无效 / 网络异常"。
enum KeyTestOutcome { valid, invalid, networkError }

class KeyTestResult {
  const KeyTestResult(this.outcome, [this.detail]);
  final KeyTestOutcome outcome;
  final String? detail;

  bool get isValid => outcome == KeyTestOutcome.valid;
  String get display {
    switch (outcome) {
      case KeyTestOutcome.valid:
        return '密钥有效';
      case KeyTestOutcome.invalid:
        return '密钥无效，请检查 API Key';
      case KeyTestOutcome.networkError:
        return '网络异常，请稍后重试${detail == null ? '' : '：$detail'}';
    }
  }
}

/// 连接验证抽象。
abstract class ConnectionTester {
  Future<KeyTestResult> testDashScope(String apiKey);
  Future<KeyTestResult> testGlm(String apiKey);
}

/// 生产实现：发最小文本请求验证 key。
/// 不发图片，避免耗图片额度（CLAUDE.md §红线#2：测试连接不耗真实识别额度）。
class HttpConnectionTester implements ConnectionTester {
  HttpConnectionTester({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  @override
  Future<KeyTestResult> testDashScope(String apiKey) =>
      _test(ApiKeyType.dashscope, apiKey);

  @override
  Future<KeyTestResult> testGlm(String apiKey) => _test(ApiKeyType.glm, apiKey);

  Future<KeyTestResult> _test(ApiKeyType which, String apiKey) async {
    if (apiKey.trim().isEmpty) {
      return const KeyTestResult(KeyTestOutcome.invalid);
    }
    final endpoint = which == ApiKeyType.dashscope
        ? AppConstants.qwenEndpoint
        : AppConstants.glmEndpoint;
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        endpoint,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          sendTimeout: AppConstants.networkTimeout,
          receiveTimeout: AppConstants.networkTimeout,
          validateStatus: (_) => true, // 自己判状态码
        ),
        data: _minimalPingBody(which),
      );
      final code = resp.statusCode ?? 0;
      if (code == 401 || code == 403) {
        return const KeyTestResult(KeyTestOutcome.invalid);
      }
      if (code >= 200 && code < 300) {
        return const KeyTestResult(KeyTestOutcome.valid);
      }
      // 非 2xx 且非 401/403：多半是 key 无效（DashScope/GLM 对错 key 返回 401，
      // 对格式错的 body 可能返回 400）。保守判 invalid。
      if (code == 400 || code == 404) {
        return KeyTestResult(KeyTestOutcome.invalid, 'HTTP $code');
      }
      return KeyTestResult(KeyTestOutcome.networkError, 'HTTP $code');
    } on DioException catch (e) {
      final msg =
          e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.connectionError
          ? null
          : e.message;
      return KeyTestResult(KeyTestOutcome.networkError, msg);
    } catch (e) {
      return KeyTestResult(KeyTestOutcome.networkError, '$e');
    }
  }

  /// 最小 ping body：1 token 文本补全，耗额度极低（≤¥0.0001 量级）。
  Map<String, dynamic> _minimalPingBody(ApiKeyType which) {
    if (which == ApiKeyType.dashscope) {
      return {
        'model': 'qwen-plus',
        'messages': [
          {'role': 'user', 'content': 'ping'},
        ],
        'max_tokens': 1,
      };
    }
    return {
      'model': 'glm-4-flash',
      'messages': [
        {'role': 'user', 'content': 'ping'},
      ],
      'max_tokens': 1,
    };
  }
}

/// 测试 / 离线实现：按 key 内容判定，零真实 API。
/// 约定（测试用）：空或 "bad" → invalid；"net-error" → networkError；其余 → valid。
@visibleForTesting
class MockConnectionTester implements ConnectionTester {
  MockConnectionTester();

  @override
  Future<KeyTestResult> testDashScope(String apiKey) => _mock(apiKey);

  @override
  Future<KeyTestResult> testGlm(String apiKey) => _mock(apiKey);

  Future<KeyTestResult> _mock(String apiKey) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final t = apiKey.trim();
    if (t.isEmpty || t == 'bad') {
      return const KeyTestResult(KeyTestOutcome.invalid);
    }
    if (t == 'net-error') {
      return const KeyTestResult(KeyTestOutcome.networkError, 'mock timeout');
    }
    return const KeyTestResult(KeyTestOutcome.valid);
  }
}
