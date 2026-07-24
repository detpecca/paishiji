// 拍食记视觉识别 Provider 抽象 + Qwen/GLM/Mock 实现 + 降级链。
// CLAUDE.md §5.1：图片 base64 内嵌直传；超时 20s/非200/解析失败 → 备 provider → 抛友好错误。
//
// 红线#2：大模型调用必须走此抽象；测试零真实 API 调用。
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:meta/meta.dart';

import '../../core/app_exceptions.dart';
import '../../core/constants.dart';
import 'image_processor.dart';

/// 大模型返回的单项识别结果（CLAUDE.md §5.1 schema）。
class VisionItem {
  const VisionItem({
    required this.name,
    required this.confidence,
    required this.estGrams,
    this.ingredients = const <String>[],
  });

  final String name;
  final double confidence;
  final int estGrams;
  final List<String> ingredients;

  Map<String, dynamic> toJson() => {
    'name': name,
    'confidence': confidence,
    'est_grams': estGrams,
    'ingredients': ingredients,
  };

  @override
  String toString() => 'VisionItem($name, conf=$confidence, ${estGrams}g)';
}

/// VisionProvider 协议。
abstract class VisionProvider {
  String get name;
  Future<List<VisionItem>> analyze(ProcessedImage image);
}

/// 阿里百炼 Qwen-VL-Max（主）。
/// OpenAI 兼容端点；图片以 data:image/jpeg;base64,... 内嵌。
class QwenVisionProvider implements VisionProvider {
  QwenVisionProvider({required this.apiKey, Dio? dio, this._prompt})
    : _dio = dio ?? Dio();

  final String apiKey;
  final Dio _dio;
  String? _prompt;

  @override
  String get name => 'qwen-vl-max';

  @override
  Future<List<VisionItem>> analyze(ProcessedImage image) async {
    if (apiKey.trim().isEmpty) {
      throw const InvalidKeyException();
    }
    final prompt = _prompt ?? await _loadPrompt();
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        AppConstants.qwenEndpoint,
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
          'model': 'qwen-vl-max',
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image_url',
                  'image_url': {'url': image.dataUrl},
                },
                {'type': 'text', 'text': prompt},
              ],
            },
          ],
          'temperature': AppConstants.visionTemperature,
        },
      );
      final code = resp.statusCode ?? 0;
      if (code == 401 || code == 403) {
        throw const InvalidKeyException();
      }
      if (code != 200) {
        throw VisionFailedException('HTTP $code');
      }
      final content = _extractContent(resp.data);
      return VisionJsonParser.parse(
        content,
      ).take(AppConstants.visionMaxItems).toList();
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

  Future<String> _loadPrompt() async {
    final p = await rootBundle.loadString('assets/prompt_food_v1.txt');
    _prompt = p;
    return p;
  }
}

/// 智谱 GLM-4V（备，用户在设置页填了第二个 key 才启用）。
class GlmVisionProvider implements VisionProvider {
  GlmVisionProvider({required this.apiKey, Dio? dio, this._prompt})
    : _dio = dio ?? Dio();

  final String apiKey;
  final Dio _dio;
  String? _prompt;

  @override
  String get name => 'glm-4v';

  @override
  Future<List<VisionItem>> analyze(ProcessedImage image) async {
    if (apiKey.trim().isEmpty) {
      throw const InvalidKeyException();
    }
    final prompt = _prompt ?? await _loadPrompt();
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        AppConstants.glmEndpoint,
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
          'model': 'glm-4v',
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image_url',
                  'image_url': {'url': image.dataUrl},
                },
                {'type': 'text', 'text': prompt},
              ],
            },
          ],
          'temperature': AppConstants.visionTemperature,
        },
      );
      final code = resp.statusCode ?? 0;
      if (code == 401 || code == 403) {
        throw const InvalidKeyException();
      }
      if (code != 200) {
        throw VisionFailedException('HTTP $code');
      }
      final content = _extractContent(resp.data);
      return VisionJsonParser.parse(
        content,
      ).take(AppConstants.visionMaxItems).toList();
    } on InvalidKeyException {
      rethrow;
    } on VisionFailedException {
      rethrow;
    } on DioException catch (e) {
      throw VisionFailedException(e.message ?? '网络异常');
    } catch (e) {
      throw VisionFailedException('$e');
    }
  }

  Future<String> _loadPrompt() async {
    final p = await rootBundle.loadString('assets/prompt_food_v1.txt');
    _prompt = p;
    return p;
  }
}

/// 测试用：返回固定识别结果，零真实 API。
@visibleForTesting
class MockVisionProvider implements VisionProvider {
  MockVisionProvider({this.items = _defaultItems, this.shouldFail = false});

  final List<VisionItem> items;
  final bool shouldFail;

  static const _defaultItems = <VisionItem>[
    VisionItem(
      name: '番茄炒蛋',
      confidence: 0.9,
      estGrams: 250,
      ingredients: ['番茄', '鸡蛋'],
    ),
    VisionItem(
      name: '米饭',
      confidence: 0.95,
      estGrams: 200,
      ingredients: ['粳米'],
    ),
  ];

  @override
  String get name => 'mock';

  @override
  Future<List<VisionItem>> analyze(ProcessedImage image) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (shouldFail) {
      throw const VisionFailedException('mock 故障');
    }
    return List.of(items);
  }
}

/// 从 OpenAI 兼容响应里抽 content 文本。
String _extractContent(Map<String, dynamic>? body) {
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
        if (part is Map && part['text'] is String)
          return part['text'] as String;
      }
    }
  }
  return '';
}

/// 解析大模型返回的 JSON 数组（prompt 要求严格 JSON 数组）。
/// 容错：剥 ``` 代码块包裹、抽第一个 [..]。
class VisionJsonParser {
  VisionJsonParser._();

  static List<VisionItem> parse(String raw) {
    final cleaned = _stripCodeFence(raw).trim();
    if (cleaned.isEmpty) return const [];
    final start = cleaned.indexOf('[');
    final end = cleaned.lastIndexOf(']');
    if (start < 0 || end < 0 || end <= start) return const [];
    final slice = cleaned.substring(start, end + 1);
    try {
      final decoded = jsonDecode(slice);
      if (decoded is! List) return const [];
      final out = <VisionItem>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final name = e['name'];
        if (name is! String || name.isEmpty) continue;
        out.add(
          VisionItem(
            name: name,
            confidence: _toDouble(e['confidence']),
            estGrams: _toInt(e['est_grams'] ?? e['estGrams']),
            ingredients:
                (e['ingredients'] as List?)?.map((i) => '$i').toList() ??
                const [],
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static String _stripCodeFence(String s) {
    if (s.startsWith('```')) {
      final nl = s.indexOf('\n');
      if (nl >= 0) s = s.substring(nl + 1);
      if (s.endsWith('```')) s = s.substring(0, s.length - 3);
    }
    return s;
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

/// VisionChain：主 provider 故障 → 备 provider → 抛友好错误。
/// 必填主；备可选（null 则直接抛主错误）。
class VisionChain implements VisionProvider {
  VisionChain({required this.primary, this.fallback});

  final VisionProvider primary;
  final VisionProvider? fallback;

  @override
  String get name =>
      'chain(${primary.name}${fallback != null ? '/${fallback!.name}' : ''})';

  @override
  Future<List<VisionItem>> analyze(ProcessedImage image) async {
    try {
      return await primary.analyze(image);
    } on InvalidKeyException {
      // key 错直接抛，不走降级（备 key 是不同供应商，但用户体验上"密钥无效"更准确）
      rethrow;
    } catch (e) {
      if (fallback == null) {
        throw VisionFailedException((e is AppException ? e.message : '$e'));
      }
      // 主故障 → 备
      try {
        return await fallback!.analyze(image);
      } on InvalidKeyException {
        rethrow;
      } catch (e2) {
        throw VisionFailedException((e2 is AppException ? e2.message : '$e2'));
      }
    }
  }
}
