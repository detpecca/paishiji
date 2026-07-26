// 拍食记条码编排。CLAUDE.md §六 Task 7：
// 扫码 → OpenFoodFactsClient → 命中展示营养+红绿灯；
// 未命中引导拍营养表 → NutritionLabelProvider 解析 → 入库 source=3 → 回到命中展示。
//
// 纯协调：依赖 OpenFoodFactsClient + NutritionLabelProvider + ImageProcessor +
// DataScope + DailyContext。所有可注入 Mock，零真实 API（红线#2）。
import 'dart:io';

import 'package:drift/drift.dart' show Value;

import '../../core/app_exceptions.dart';
import '../../core/date_key.dart';
import '../../data/data.dart';
import '../../domain/nutrition_matcher.dart';
import '../../domain/traffic_light_engine.dart';
import 'image_processor.dart';
import 'nutrition_label_provider.dart';
import 'open_food_facts.dart';

/// 条码流程的单步结果。命中返回 [BarcodeResult] 与红绿灯；未命中返回 null。
class BarcodeFlowResult {
  const BarcodeFlowResult({
    required this.barcode,
    required this.foodRecord,
    required this.signal,
    required this.advice,
    this.fromCache = false,
  });

  final String barcode;
  final FoodRecord foodRecord;
  final Signal signal;
  final String advice;
  final bool fromCache; // 二次扫码命中本地库
}

/// 条码流程编排器。
class BarcodeFlow {
  BarcodeFlow({
    required this.openFoodFacts,
    required this.labelProvider,
    required this.imageProcessor,
    required this.scope,
  });

  final OpenFoodFactsClient openFoodFacts;
  final NutritionLabelProvider labelProvider;
  final ImageProcessor imageProcessor;
  final DataScope scope;

  /// 扫码后第一步：先查本地库（二次扫码直接命中），再查 Open Food Facts。
  /// 命中返回 [BarcodeFlowResult]；未命中返回 null，调用方引导拍营养表。
  Future<BarcodeFlowResult?> lookup(String barcode) async {
    final b = barcode.trim();
    if (b.isEmpty) return null;
    // 1. 本地库按 barcode 命中 → 二次扫码直接命中（DoD）。
    final local = await scope.foodsDao.findByBarcode(b);
    if (local != null) {
      return BarcodeFlowResult(
        barcode: b,
        foodRecord: _toRecord(local),
        signal: Signal.green,
        advice: '已从本地库命中',
        fromCache: true,
      );
    }
    // 2. Open Food Facts。
    final remote = await openFoodFacts.lookup(b);
    if (remote == null) return null;
    // 命中：入库 source=3 verified=0，barcode 唯一。
    final foodId = await _ingest(remote, b);
    final food = await scope.foodsDao.findById(foodId);
    if (food == null) {
      throw const VisionFailedException('条码入库失败');
    }
    return BarcodeFlowResult(
      barcode: b,
      foodRecord: _toRecord(food),
      signal: Signal.green,
      advice: '已从 Open Food Facts 命中',
    );
  }

  /// 未命中第二步：拍营养表 → 大模型解析 → 入库 source=3 → 返回流程结果。
  Future<BarcodeFlowResult> supplementFromLabel({
    required String barcode,
    required String imagePath,
  }) async {
    final b = barcode.trim();
    final file = File(imagePath);
    final processed = await imageProcessor.processFile(file);
    final label = await labelProvider.analyze(processed);
    // 入库 source=3 verified=0，barcode 关联。
    final foodId = await scope.foodsDao.upsertByBarcode(
      FoodsCompanion.insert(
        name: label.name,
        aliases: const Value('[]'),
        caloriesPer100g: label.caloriesPer100g,
        proteinPer100g: label.proteinPer100g,
        carbsPer100g: label.carbsPer100g,
        fatPer100g: label.fatPer100g,
        sugarPer100g: Value(label.sugarPer100g),
        fiberPer100g: Value(label.fiberPer100g),
        sodiumPer100g: Value(label.sodiumPer100g),
        source: 3,
        verified: const Value(0),
        barcode: Value(b),
      ),
    );
    final food = await scope.foodsDao.findById(foodId);
    if (food == null) {
      throw const VisionFailedException('营养表入库失败');
    }
    return BarcodeFlowResult(
      barcode: b,
      foodRecord: _toRecord(food),
      signal: Signal.green,
      advice: '已从营养表补录',
    );
  }

  /// 把 BarcodeResult / Food 落库（Open Food Facts 命中路径）。
  Future<int> _ingest(BarcodeResult r, String barcode) {
    return scope.foodsDao.upsertByBarcode(
      FoodsCompanion.insert(
        name: r.name,
        aliases: const Value('[]'),
        caloriesPer100g: r.caloriesPer100g,
        proteinPer100g: r.proteinPer100g,
        carbsPer100g: r.carbsPer100g,
        fatPer100g: r.fatPer100g,
        sugarPer100g: Value(r.sugarPer100g),
        fiberPer100g: Value(r.fiberPer100g),
        sodiumPer100g: Value(r.sodiumPer100g),
        source: 3,
        verified: const Value(0),
        barcode: Value(barcode),
      ),
    );
  }

  FoodRecord _toRecord(Food f) => FoodRecord(
    id: f.id,
    name: f.name,
    aliasesJson: f.aliases,
    caloriesPer100g: f.caloriesPer100g,
    proteinPer100g: f.proteinPer100g,
    carbsPer100g: f.carbsPer100g,
    fatPer100g: f.fatPer100g,
    sugarPer100g: f.sugarPer100g,
    fiberPer100g: f.fiberPer100g,
    sodiumPer100g: f.sodiumPer100g,
    barcode: f.barcode,
  );
}

/// 给 BarcodeFlowResult 计算红绿灯（基于当日上下文 + 克重）。
/// 单独函数，便于 UI 滑块联动复用。
TrafficLightResult evaluateBarcodeTrafficLight({
  required FoodRecord food,
  required int grams,
  required DailyContext daily,
}) {
  final fn = FoodNutrition(
    name: food.name,
    grams: grams,
    caloriesPer100g: food.caloriesPer100g,
    proteinPer100g: food.proteinPer100g,
    carbsPer100g: food.carbsPer100g,
    fatPer100g: food.fatPer100g,
    sugarPer100g: food.sugarPer100g,
    fiberPer100g: food.fiberPer100g,
  );
  return TrafficLightEngine.evaluate(food: fn, daily: daily);
}

/// 今天日期键（供 UI 默认归档用）。
String barcodeDefaultLoggedDate() => DateKey.today();

/// 条码归档：写 meal_entries（克重 + 餐次 + 当日实时营养）。
Future<int> archiveBarcodeEntry({
  required DataScope scope,
  required int foodId,
  required int grams,
  required int mealType,
  required double calories,
  required double protein,
  required double carbs,
  required double fat,
}) async {
  return scope.mealEntriesDao.add(
    MealEntriesCompanion.insert(
      foodId: foodId,
      grams: grams,
      mealType: mealType,
      loggedDate: DateKey.today(),
      calories: calories,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
    ),
  );
}

// 让 BarcodeFlow 的 lookup/supplement 抛出的 AppException 在 UI 直接 .message 展示。
String barcodeErrorMessage(Object e) => e is AppException ? e.message : '$e';
