// 拍食记视觉识别 Provider 抽象 + Qwen/GLM/Mock/Custom 实现 + 降级链。
// CLAUDE.md §5.1：图片 base64 内嵌直传；超时 20s/非200/解析失败 → 备 provider → 抛友好错误。
//
// 红线#2：大模型调用必须走此抽象；测试零真实 API 调用。
//
// Qwen/GLM/Custom 共用 OpenAICompatibleProvider mixin（dio POST + 响应抽取 + 错误映射），
// 区别只有 baseUrl/model/apiKey 三个字段。Custom 让用户填任意 OpenAI 兼容端点（如 Kimi）。
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:meta/meta.dart';

import '../../core/app_exceptions.dart';
import '../../core/constants.dart';
import 'image_processor.dart';
import 'openai_compatible_provider.dart';

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

/// 阿里百炼 Qwen-VL-Max（OpenAI 兼容端点）。
class QwenVisionProvider
    with OpenAICompatibleProvider
    implements VisionProvider {
  QwenVisionProvider({required this.apiKey, Dio? dio, String? prompt})
    : _dio = dio ?? Dio(),
      _prompt = prompt;

  @override
  final String apiKey;
  final Dio _dio;
  String? _prompt;

  @override
  String get baseUrl => AppConstants.qwenEndpoint;
  @override
  String get model => 'qwen-vl-max';
  @override
  Dio get dio => _dio;

  @override
  String get name => model;

  @override
  Future<List<VisionItem>> analyze(ProcessedImage image) async {
    final prompt = _prompt ?? await _loadPrompt();
    _prompt = prompt;
    final content = await postChat(prompt: prompt, imageDataUrl: image.dataUrl);
    return VisionJsonParser.parse(
      content,
    ).take(AppConstants.visionMaxItems).toList();
  }

  Future<String> _loadPrompt() async {
    final p = await rootBundle.loadString('assets/prompt_food_v1.txt');
    _prompt = p;
    return p;
  }
}

/// 智谱 GLM-4V（备，用户在设置页填了第二个 key 才启用）。
class GlmVisionProvider
    with OpenAICompatibleProvider
    implements VisionProvider {
  GlmVisionProvider({required this.apiKey, Dio? dio, String? prompt})
    : _dio = dio ?? Dio(),
      _prompt = prompt;

  @override
  final String apiKey;
  final Dio _dio;
  String? _prompt;

  @override
  String get baseUrl => AppConstants.glmEndpoint;
  @override
  String get model => 'glm-4v';
  @override
  Dio get dio => _dio;

  @override
  String get name => model;

  @override
  Future<List<VisionItem>> analyze(ProcessedImage image) async {
    final prompt = _prompt ?? await _loadPrompt();
    _prompt = prompt;
    final content = await postChat(prompt: prompt, imageDataUrl: image.dataUrl);
    return VisionJsonParser.parse(
      content,
    ).take(AppConstants.visionMaxItems).toList();
  }

  Future<String> _loadPrompt() async {
    final p = await rootBundle.loadString('assets/prompt_food_v1.txt');
    _prompt = p;
    return p;
  }
}

/// 自定义 OpenAI 兼容端点（Kimi / 豆包 / Volcengine 等）。
/// baseUrl/model/apiKey 全从用户配置读，不硬编码任何厂商信息。
class CustomVisionProvider
    with OpenAICompatibleProvider
    implements VisionProvider {
  CustomVisionProvider({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    Dio? dio,
    String? prompt,
  }) : _dio = dio ?? Dio(),
       _prompt = prompt;

  @override
  final String baseUrl;
  @override
  final String model;
  @override
  final String apiKey;
  final Dio _dio;
  String? _prompt;

  @override
  Dio get dio => _dio;

  @override
  String get name => 'custom:$model';

  @override
  Future<List<VisionItem>> analyze(ProcessedImage image) async {
    final prompt = _prompt ?? await _loadPrompt();
    _prompt = prompt;
    final content = await postChat(prompt: prompt, imageDataUrl: image.dataUrl);
    return VisionJsonParser.parse(
      content,
    ).take(AppConstants.visionMaxItems).toList();
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
  const MockVisionProvider({
    this.items = _defaultItems,
    this.shouldFail = false,
  });

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
  const VisionChain({required this.primary, this.fallback});

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
