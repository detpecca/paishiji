// 拍食记识别结果页状态。CLAUDE.md §六 Task 5：
// - 份量滑块（50g 步进）营养实时联动
// - 低置信度（<0.7）黄条警示 + 候选列表点选纠正
// - "不对？纠正"换食物/改份量/文字补充后重识别
// - "存入今日"按餐次归档（写 meal_entries）
//
// 纯 Dart 可测部分：重算逻辑（grams 变 → 营养 + 红绿灯重算）。
import 'package:flutter/foundation.dart';

import '../../core/constants.dart';
import '../../data/data.dart';
import '../../data/providers/recognition_pipeline.dart';
import '../../domain/nutrition_matcher.dart';
import '../../domain/traffic_light_engine.dart';

/// 单条可编辑识别项（含原始匹配的每 100g 营养，用于 grams 联动重算）。
class EditableItem extends ChangeNotifier {
  EditableItem({
    required this.view,
    required FoodRecord per100g,
    required this.daily,
    required this.sugarPer100g,
  }) : _per100g = per100g,
       _grams = view.estGrams;

  final RecognizedItemView view;
  final DailyContext daily;
  final double sugarPer100g;
  int _grams;

  /// 匹配到的食物（每 100g 营养）；未命中时 caloriesPer100g=0。
  FoodRecord _per100g;

  int get grams => _grams;
  bool get lowConfidence =>
      view.confidence < AppConstants.lowConfidenceThreshold;
  bool get unmatched => view.foodId == null;

  /// 当前克重下的营养（实时联动，不闪烁：纯本地重算，无 async）。
  double get calories => _per100g.caloriesPer100g * _grams / 100;
  double get protein => _per100g.proteinPer100g * _grams / 100;
  double get carbs => _per100g.carbsPer100g * _grams / 100;
  double get fat => _per100g.fatPer100g * _grams / 100;

  /// 当前克重下的红绿灯（实时联动重算）。
  TrafficLightResult get trafficLight {
    final food = FoodNutrition(
      name: view.detectedName,
      grams: _grams,
      caloriesPer100g: _per100g.caloriesPer100g,
      proteinPer100g: _per100g.proteinPer100g,
      carbsPer100g: _per100g.carbsPer100g,
      fatPer100g: _per100g.fatPer100g,
      sugarPer100g: sugarPer100g,
    );
    return TrafficLightEngine.evaluate(food: food, daily: daily);
  }

  /// 份量滑块改（50g 步进）。
  void setGrams(int v) {
    final stepped = (v ~/ 50) * 50;
    if (stepped < 50) {
      _grams = 50;
    } else {
      _grams = stepped;
    }
    notifyListeners();
  }

  /// 候选纠正：换到另一个食物。保留 grams（CLAUDE.md：换食物不重置份量）。
  void swapTo(FoodRecord other) {
    _per100g = other;
    notifyListeners();
  }

  /// 当前匹配的食物（可被 swapTo 替换）。
  FoodRecord get currentFood => _per100g;
}

/// 整餐可编辑状态。N 项 + 选中餐次。
class RecognitionDraft extends ChangeNotifier {
  RecognitionDraft({required this.items, this.mealType = 2});

  final List<EditableItem> items;
  int mealType; // 1早 2午 3晚 4加餐

  /// 整餐合计（实时联动）。
  double get totalCalories => items.fold(0, (s, i) => s + i.calories);
  double get totalProtein => items.fold(0, (s, i) => s + i.protein);
  double get totalCarbs => items.fold(0, (s, i) => s + i.carbs);
  double get totalFat => items.fold(0, (s, i) => s + i.fat);

  void setMealType(int t) {
    mealType = t;
    notifyListeners();
  }
}

/// "存入今日"归档结果。
class ArchiveResult {
  const ArchiveResult({required this.writtenIds});
  final List<int> writtenIds; // meal_entries.id 列表
}

/// 识别控制器：协调 draft 与 DataScope。
@visibleForTesting
class RecognitionController {
  RecognitionController({required this.scope, required this.draft});

  final DataScope scope;
  final RecognitionDraft draft;

  /// 存入今日：每项写 meal_entries（红线#1：UI 热量带估算角标，但落库的是当前实时营养）。
  ///
  /// Task 7：未命中项在 pipeline 里已入库 source=2 并拿到 foodId，
  /// 故此处不再跳过——所有项均可落 meal_entries。
  Future<ArchiveResult> archiveToday(String loggedDate) async {
    final ids = <int>[];
    for (final it in draft.items) {
      final foodId = it.view.foodId;
      if (foodId == null) {
        // 估算器未注入的回退分支：跳过未命中项（meal_entries 有 food_id 外键）。
        continue;
      }
      final id = await scope.mealEntriesDao.add(
        MealEntriesCompanion.insert(
          foodId: foodId,
          grams: it.grams,
          mealType: draft.mealType,
          loggedDate: loggedDate,
          calories: it.calories,
          proteinG: it.protein,
          carbsG: it.carbs,
          fatG: it.fat,
        ),
      );
      ids.add(id);
    }
    return ArchiveResult(writtenIds: ids);
  }
}
