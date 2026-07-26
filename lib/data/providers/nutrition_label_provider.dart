// 拍食记营养表识别。CLAUDE.md §六 Task 7：
// 未命中条码 → 引导拍营养表 → 大模型解析 → 入库 source=3, verified=0。
//
// 复用 VisionProvider 抽象的"调大模型"部分（prompt + Qwen/GLM），但返回结构不同
// （不是菜名列表，是单一营养对象）。为保持 VisionProvider 协议（List<VisionItem>）的
// 单一职责，本文件另立 NutritionLabelProvider 协议，返回 LabelNutrition。
//
// 红线#2：Mock 实现零真实 API；测试可离线运行。
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:meta/meta.dart';

import '../../core/app_exceptions.dart';
import '../../core/constants.dart';
import 'image_processor.dart';

/// 营养表解析结果（每 100g 营养）。
class LabelNutrition {
  const LabelNutrition({
    required this.name,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    this.sugarPer100g = 0,
    this.fiberPer100g = 0,
    this.sodiumPer100g = 0,
  });

  final String name;
  final double caloriesPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final double sugarPer100g;
  final double fiberPer100g;
  final double sodiumPer100g;
}

/// 营养表识别抽象（与 VisionProvider 平行，但返回单一营养对象）。
abstract class NutritionLabelProvider {
  String get name;
  Future<LabelNutrition> analyze(ProcessedImage image);
}

/// 阿里百炼 Qwen-VL-Max 实现（主）。复用 prompt_label_v1.txt。
class QwenLabelProvider implements NutritionLabelProvider {
  QwenLabelProvider({required this.apiKey, Dio? dio, String? prompt})
    : _dio = dio ?? Dio(),
      _prompt = prompt;

  final String apiKey;
  final Dio _dio;
  String? _prompt;

  @override
  String get name => 'qwen-label';

  @override
  Future<LabelNutrition> analyze(ProcessedImage image) async {
    if (apiKey.trim().isEmpty) throw const InvalidKeyException();
    final prompt = _prompt ?? await _loadPrompt();
    _prompt = prompt;
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
      if (code == 401 || code == 403) throw const InvalidKeyException();
      if (code != 200) throw VisionFailedException('HTTP $code');
      final content = _extractContent(resp.data);
      final parsed = LabelJsonParser.parse(content);
      if (parsed == null) {
        throw const VisionFailedException('营养表解析失败');
      }
      return parsed;
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
    final p = await rootBundle.loadString('assets/prompt_label_v1.txt');
    _prompt = p;
    return p;
  }
}

/// 智谱 GLM-4V 实现（备）。
class GlmLabelProvider implements NutritionLabelProvider {
  GlmLabelProvider({required this.apiKey, Dio? dio, String? prompt})
    : _dio = dio ?? Dio(),
      _prompt = prompt;

  final String apiKey;
  final Dio _dio;
  String? _prompt;

  @override
  String get name => 'glm-label';

  @override
  Future<LabelNutrition> analyze(ProcessedImage image) async {
    if (apiKey.trim().isEmpty) throw const InvalidKeyException();
    final prompt = _prompt ?? await _loadPrompt();
    _prompt = prompt;
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
      if (code == 401 || code == 403) throw const InvalidKeyException();
      if (code != 200) throw VisionFailedException('HTTP $code');
      final content = _extractContent(resp.data);
      final parsed = LabelJsonParser.parse(content);
      if (parsed == null) {
        throw const VisionFailedException('营养表解析失败');
      }
      return parsed;
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
    final p = await rootBundle.loadString('assets/prompt_label_v1.txt');
    _prompt = p;
    return p;
  }
}

/// 测试 / 离线实现：返回固定营养表数据，零真实 API。
@visibleForTesting
class MockLabelProvider implements NutritionLabelProvider {
  const MockLabelProvider({this.result, this.shouldFail = false});

  final LabelNutrition? result;
  final bool shouldFail;

  static const LabelNutrition defaultResult = LabelNutrition(
    name: '某品牌苏打饼干',
    caloriesPer100g: 435,
    proteinPer100g: 8,
    carbsPer100g: 64,
    fatPer100g: 20,
    sugarPer100g: 18,
    fiberPer100g: 3,
    sodiumPer100g: 0.48,
  );

  @override
  String get name => 'mock-label';

  @override
  Future<LabelNutrition> analyze(ProcessedImage image) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (shouldFail) {
      throw const VisionFailedException('mock 营养表解析失败');
    }
    return result ?? defaultResult;
  }
}

/// 从 OpenAI 兼容响应里抽 content 文本（与 vision_provider 同结构）。
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
        if (part is Map && part['text'] is String) {
          return part['text'] as String;
        }
      }
    }
  }
  return '';
}

/// 解析大模型返回的营养表 JSON 对象。容错：剥 ```、抽第一个 {..}。
class LabelJsonParser {
  LabelJsonParser._();

  static LabelNutrition? parse(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      final nl = s.indexOf('\n');
      if (nl >= 0) s = s.substring(nl + 1);
      if (s.endsWith('```')) s = s.substring(0, s.length - 3);
    }
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start < 0 || end < 0 || end <= start) return null;
    final slice = s.substring(start, end + 1);
    try {
      final m = jsonDecode(slice) as Map<String, dynamic>;
      final name = m['name']?.toString() ?? '';
      if (name.trim().isEmpty) return null;
      return LabelNutrition(
        name: name,
        caloriesPer100g: _toDouble(m['calories_per_100g']),
        proteinPer100g: _toDouble(m['protein_per_100g']),
        carbsPer100g: _toDouble(m['carbs_per_100g']),
        fatPer100g: _toDouble(m['fat_per_100g']),
        sugarPer100g: _toDouble(m['sugar_per_100g']),
        fiberPer100g: _toDouble(m['fiber_per_100g']),
        sodiumPer100g: _toDouble(m['sodium_per_100g']),
      );
    } catch (_) {
      return null;
    }
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

/// LabelChain：主故障 → 备 → 抛友好错误。
class LabelChain implements NutritionLabelProvider {
  LabelChain({required this.primary, this.fallback});

  final NutritionLabelProvider primary;
  final NutritionLabelProvider? fallback;

  @override
  String get name =>
      'label-chain(${primary.name}${fallback != null ? '/${fallback!.name}' : ''})';

  @override
  Future<LabelNutrition> analyze(ProcessedImage image) async {
    try {
      return await primary.analyze(image);
    } on InvalidKeyException {
      rethrow;
    } catch (e) {
      if (fallback == null) {
        throw VisionFailedException(e is AppException ? e.message : '$e');
      }
      try {
        return await fallback!.analyze(image);
      } on InvalidKeyException {
        rethrow;
      } catch (e2) {
        throw VisionFailedException(e2 is AppException ? e2.message : '$e2');
      }
    }
  }
}
