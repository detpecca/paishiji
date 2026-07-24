// 拍食记识别编排 pipeline。CLAUDE.md §六 Task 4：图片压缩 → VisionProvider
// → JSON 解析 → 营养库匹配 → 红黄绿灯 → 写库。
//
// 纯协调，无业务判断；业务规则在 domain/* 纯函数里。
// 红线#2：全链路可挂 Mock，零真实 API。
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:meta/meta.dart';

import '../../domain/nutrition_matcher.dart';
import '../../domain/traffic_light_engine.dart';
import '../data.dart';
import 'image_processor.dart';
import 'vision_provider.dart';

/// 识别后单项的可展示结果（已含红绿灯与营养）。
class RecognizedItemView {
  const RecognizedItemView({
    required this.detectedName,
    required this.confidence,
    required this.estGrams,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.signal,
    required this.advice,
    this.foodId,
    this.candidates = const <FoodRecord>[],
  });

  final String detectedName;
  final double confidence;
  final int estGrams;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final Signal signal;
  final String advice;
  final int? foodId;
  final List<FoodRecord> candidates;
}

/// 识别结果视图。
class RecognitionResultView {
  const RecognitionResultView({
    required this.items,
    required this.recognitionId,
    required this.provider,
    required this.latencyMs,
  });

  final List<RecognizedItemView> items;
  final int recognitionId;
  final String provider;
  final int latencyMs;

  double get totalCalories => items.fold(0, (s, i) => s + i.calories);
}

/// 识别编排器。注入 ImageProcessor + VisionChain + DataScope + 当日上下文。
class RecognitionPipeline {
  RecognitionPipeline({
    required this.imageProcessor,
    required this.vision,
    required this.scope,
    required this.daily,
  });

  final ImageProcessor imageProcessor;
  final VisionProvider vision;
  final DataScope scope;
  final DailyContext daily;

  /// 跑完整链路：压缩 → 识别 → 匹配 → 红绿灯 → 写库。
  /// [imagePath] 用于写 recognitions.image_path（库内只存路径，红线#4 created_at 自动）。
  Future<RecognitionResultView> run(String imagePath, {File? imageFile}) async {
    final started = _nowMillis();
    final file = imageFile ?? File(imagePath);
    final processed = await imageProcessor.processFile(file);
    final items = await vision.analyze(processed);
    final latency = _nowMillis() - started;

    // 写 recognitions 头表（raw_json 存大模型原始 VisionItem 摘要）
    final rid = await scope.recognitionsDao.createRecognition(
      imagePath: imagePath,
      provider: vision.name,
      latencyMs: latency,
      rawJson: _encodeRaw(items),
    );

    final views = <RecognizedItemView>[];
    for (final v in items) {
      views.add(await _resolveItem(v, rid));
    }
    return RecognitionResultView(
      items: views,
      recognitionId: rid,
      provider: vision.name,
      latencyMs: latency,
    );
  }

  Future<RecognizedItemView> _resolveItem(VisionItem v, int rid) async {
    final foods = await scope.foodsDao.all();
    final records = foods
        .map(
          (f) => FoodRecord(
            id: f.id,
            name: f.name,
            aliasesJson: f.aliases,
            caloriesPer100g: f.caloriesPer100g,
            proteinPer100g: f.proteinPer100g,
            carbsPer100g: f.carbsPer100g,
            fatPer100g: f.fatPer100g,
          ),
        )
        .toList();

    final match = NutritionMatcher.match(detectedName: v.name, foods: records);

    FoodNutrition food;
    int? foodId;
    if (match.isFound) {
      final r = match.record!;
      foodId = r.id;
      food = FoodNutrition(
        name: r.name,
        grams: v.estGrams,
        caloriesPer100g: r.caloriesPer100g,
        proteinPer100g: r.proteinPer100g,
        carbsPer100g: r.carbsPer100g,
        fatPer100g: r.fatPer100g,
        sugarPer100g: 0,
      );
    } else {
      // 未命中：用大模型估算的克重 + 暂置每100g 营养为 0，标红"待确认"
      food = FoodNutrition(
        name: v.name,
        grams: v.estGrams,
        caloriesPer100g: 0,
        proteinPer100g: 0,
        carbsPer100g: 0,
        fatPer100g: 0,
        sugarPer100g: 0,
      );
    }

    final tlr = TrafficLightEngine.evaluate(food: food, daily: daily);
    final calories = food.totalCalories;
    final protein = food.totalProtein;
    final carbs = food.caloriesPer100g * v.estGrams / 100;
    final fat = food.totalFat;

    // 写 recognition_items（红线#4 created_at 自动）
    await scope.recognitionsDao.addItems([
      RecognitionItemsCompanion.insert(
        recognitionId: rid,
        detectedName: v.name,
        confidence: v.confidence,
        estGrams: v.estGrams,
        calories: calories,
        proteinG: protein,
        carbsG: carbs,
        fatG: fat,
        signal: tlr.signal.code,
        adviceText: Value(tlr.advice),
        foodId: foodId == null ? const Value.absent() : Value(foodId),
        candidatesJson: Value(_encodeCandidates(match.candidates)),
      ),
    ]);

    return RecognizedItemView(
      detectedName: v.name,
      confidence: v.confidence,
      estGrams: v.estGrams,
      calories: calories,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
      signal: tlr.signal,
      advice: tlr.advice,
      foodId: foodId,
      candidates: match.candidates,
    );
  }

  String _encodeRaw(List<VisionItem> items) {
    // 简要 JSON，避免 raw_json 过大。
    final list = items.map((i) => i.toJson()).toList();
    return list.toString();
  }

  String _encodeCandidates(List<FoodRecord> cs) {
    if (cs.isEmpty) return '[]';
    return '[${cs.map((c) => '{"id":${c.id},"name":"${c.name}"}').join(',')}]';
  }

  int _nowMillis() => DateTime.now().millisecondsSinceEpoch;
}

/// 测试用：跳过真实文件 IO，直接喂字节。
@visibleForTesting
class RecognitionPipelineTester {
  RecognitionPipelineTester(this.pipeline);
  final RecognitionPipeline pipeline;

  Future<RecognitionResultView> runWithBytes(
    String imagePath,
    List<int> bytes,
  ) {
    return pipeline.run(
      imagePath,
      imageFile: File.fromRawPath(Uint8List.fromList(bytes)),
    );
  }
}
