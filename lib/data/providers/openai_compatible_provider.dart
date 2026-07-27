// OpenAI 兼容端点的公共 HTTP 逻辑。
//
// 现状：QwenVisionProvider / GlmVisionProvider / QwenLabelProvider / GlmLabelProvider
// / QwenEstimateProvider 的 dio POST + 响应抽取 + 错误映射代码几乎逐字相同，
// 区别只有 baseUrl / model / apiKey 三个字段。抽成 mixin 后：
// - 现有 Qwen/GLM provider 变薄包装（行为零变化）
// - 自定义 provider（Kimi 等任意 OpenAI 兼容厂商）只需喂三个字段即可接入
//
// 红线#2：大模型调用必须走 Provider 抽象；测试零真实 API。
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/app_exceptions.dart';
import '../../core/constants.dart';

/// OpenAI 兼容 chat completions 端点的通用 HTTP 逻辑。
///
/// baseUrl / model / apiKey 都从实现类 getter 读，不再硬编码。
/// 实现类负责加载 prompt + 解析返回文本（各自解析器不同）。
mixin OpenAICompatibleProvider {
  /// 兼容端点，如 `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions`。
  String get baseUrl;

  /// 模型名，如 `qwen-vl-max` / `glm-4v` / 用户填的自定义模型名。
  String get model;

  /// Bearer token。
  String get apiKey;

  /// dio 实例（测试可注入 mock dio）。
  Dio get dio;

  /// 发一次 chat completions 请求，返回 content 文本。
  ///
  /// 抛：
  /// - `InvalidKeyException`：空 key / HTTP 401 / 403（不触发降级链）
  /// - `VisionFailedException`：其他 HTTP 错误 / 超时 / 网络异常
  Future<String> postChat({
    required String prompt,
    required String imageDataUrl,
    double? temperature,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const InvalidKeyException();
    }
    try {
      final resp = await dio.post<Map<String, dynamic>>(
        baseUrl,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          sendTimeout: AppConstants.networkTimeout,
          receiveTimeout: AppConstants.networkTimeout,
          validateStatus: (_) => true,
        ),
        data: {
          'model': model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image_url',
                  'image_url': {'url': imageDataUrl},
                },
                {'type': 'text', 'text': prompt},
              ],
            },
          ],
          'temperature': temperature ?? AppConstants.visionTemperature,
        },
      );
      final code = resp.statusCode ?? 0;
      if (code == 401 || code == 403) {
        throw const InvalidKeyException();
      }
      if (code != 200) {
        throw VisionFailedException('HTTP $code');
      }
      return extractContent(resp.data);
    } on InvalidKeyException {
      rethrow;
    } on VisionFailedException {
      rethrow;
    } on DioException catch (e) {
      throw VisionFailedException(
        e.type == DioExceptionType.receiveTimeout
            ? '请求超时'
            : e.message ?? '网络异常',
      );
    } catch (e) {
      throw VisionFailedException('$e');
    }
  }
}

/// 从 OpenAI 兼容响应里抽 content 文本。
///
/// content 可能是 String，也可能是 List<{text: ...}>（多模态返回格式）。
/// 任何畸形结构都返回空串（让上层解析器判空）。
String extractContent(Map<String, dynamic>? body) {
  if (body == null) return '';
  final choices = body['choices'];
  if (choices is! List || choices.isEmpty) return '';
  final first = choices[0];
  if (first is! Map) return '';
  final message = first['message'];
  if (message is Map) {
    final c = message['content'];
    if (c is String) return c;
    if (c is List) {
      for (final part in c) {
        if (part is Map && part['text'] is String) {
          return part['text'] as String;
        }
      }
    }
  }
  return '';
}

/// 给 OpenAI 兼容端点发"最小 ping"：1 token 文本补全，不耗图片额度。
/// 供 ConnectionTester.testCustom 用，验证 key 有效性而不烧识别钱。
Map<String, dynamic> minimalPingBody(String model) => {
  'model': model,
  'messages': [
    {'role': 'user', 'content': 'ping'},
  ],
  'max_tokens': 1,
};

/// 解析一条用户消息文本（仅给测试用，确保 MinimalPing body 合法）。
String encodePingBody(String model) => jsonEncode(minimalPingBody(model));
