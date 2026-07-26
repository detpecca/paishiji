// 拍食记未命中食物的营养估算。CLAUDE.md §5.4：
// detected_name 未命中营养库 → 调大模型按标准做法估算每 100g 营养 → 入库 source=2 verified=0。
//
// 与 NutritionLabelProvider 平行：label 是拍包装营养表，estimate 是给一道菜估营养。
// 红线#2：Mock 实现零真实 API；测试可离线运行。真 key 到位前 router 注入 Mock。
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:meta/meta.dart';

import '../../core/app_exceptions.dart';
import '../../core/constants.dart';
import 'image_processor.dart';
import 'nutrition_label_provider.dart' show LabelJsonParser, LabelNutrition;

/// 每 100g 营养估算结果。
class NutritionEstimate {
  const NutritionEstimate({
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    this.sugarPer100g = 0,
    this.fiberPer100g = 0,
    this.sodiumPer100g = 0,
  });

  final double caloriesPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final double sugarPer100g;
  final double fiberPer100g;
  final double sodiumPer100g;
}

/// 营养估算抽象。输入菜名+食材+图片，输出每 100g 营养。
abstract class NutritionEstimateProvider {
  Future<NutritionEstimate> estimate({
    required String name,
    required List<String> ingredients,
    required ProcessedImage image,
  });
}

/// 阿里百炼 Qwen-VL-Max 实现（主）。复用 prompt_estimate_v1.txt。
class QwenEstimateProvider implements NutritionEstimateProvider {
  QwenEstimateProvider({required this.apiKey, Dio? dio, String? prompt})
    : _dio = dio ?? Dio(),
      _prompt = prompt;

  final String apiKey;
  final Dio _dio;
  String? _prompt;

  @override
  Future<NutritionEstimate> estimate({
    required String name,
    required List<String> ingredients,
    required ProcessedImage image,
  }) async {
    if (apiKey.trim().isEmpty) throw const InvalidKeyException();
    final basePrompt = _prompt ?? await _loadPrompt();
    _prompt = basePrompt;
    final prompt = '$basePrompt\n\n菜名：$name，食材：${ingredients.join(",")}。';
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
        throw const VisionFailedException('营养估算解析失败');
      }
      return _fromLabel(parsed);
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
    final p = await rootBundle.loadString('assets/prompt_estimate_v1.txt');
    _prompt = p;
    return p;
  }

  static NutritionEstimate _fromLabel(LabelNutrition l) => NutritionEstimate(
    caloriesPer100g: l.caloriesPer100g,
    proteinPer100g: l.proteinPer100g,
    carbsPer100g: l.carbsPer100g,
    fatPer100g: l.fatPer100g,
    sugarPer100g: l.sugarPer100g,
    fiberPer100g: l.fiberPer100g,
    sodiumPer100g: l.sodiumPer100g,
  );
}

/// 测试 / 离线实现：按菜名查固定估算表，零真实 API（红线#2）。
/// 未在表中的菜名返回一个保守中位数估算（120kcal/10g 蛋白/15g 碳/5g 脂）。
@visibleForTesting
class MockEstimateProvider implements NutritionEstimateProvider {
  const MockEstimateProvider({this.latencyMs = 5});

  final int latencyMs;

  @override
  Future<NutritionEstimate> estimate({
    required String name,
    required List<String> ingredients,
    required ProcessedImage image,
  }) async {
    await Future<void>.delayed(Duration(milliseconds: latencyMs));
    final hit = _mockEstimates[name];
    if (hit != null) return hit;
    return const NutritionEstimate(
      caloriesPer100g: 120,
      proteinPer100g: 10,
      carbsPer100g: 15,
      fatPer100g: 5,
      sugarPer100g: 2,
      fiberPer100g: 1,
      sodiumPer100g: 0.3,
    );
  }

  /// Mock 估算表（参照中国食物成分表常见值）。
  static const _mockEstimates = <String, NutritionEstimate>{
    '宫保鸡丁': NutritionEstimate(
      caloriesPer100g: 195,
      proteinPer100g: 15,
      carbsPer100g: 6,
      fatPer100g: 11,
      sugarPer100g: 3,
      fiberPer100g: 1,
      sodiumPer100g: 0.5,
    ),
    '麻婆豆腐': NutritionEstimate(
      caloriesPer100g: 130,
      proteinPer100g: 8,
      carbsPer100g: 4,
      fatPer100g: 9,
      sodiumPer100g: 0.6,
    ),
  };
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
        if (part is Map && part['text'] is String) {
          return part['text'] as String;
        }
      }
    }
  }
  return '';
}
