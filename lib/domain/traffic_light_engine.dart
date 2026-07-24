// 拍食记红黄绿灯引擎。CLAUDE.md §5.2：纯函数，规则优先级自上而下、命中即停。
//
// R1 命中禁忌/过敏 → 🔴"含你的禁忌食材：{x}"
// R2 单品热量 > 当日剩余预算 → 🔴"这一份{cal}kcal，超过今天剩余的{budget}kcal预算"
// R3 减脂 && (糖>20g/100g || 脂肪>20g/100g) → 🔴"高糖/高脂，减脂期不建议"
// R4 蛋白质≥15g/100g && 脂肪≤10g/100g && 预算内 → 🟢"高蛋白低脂，今天蛋白质还差{gap}g，放心吃"
// R5 热量 ≤ 剩余预算30% → 🟢"占今日预算{pct}%，在计划内"
// R6 其他 → 🟡"可以吃，注意份量，建议{建议克重}g左右"
//
// 阈值集中在 AppConstants（设置页可改）。100% 单测覆盖含优先级冲突。
import '../core/constants.dart';

/// 信号灯：0绿 1黄 2红（对齐 recognition_items.signal 列）。
enum Signal {
  green(0, '🟢'),
  yellow(1, '🟡'),
  red(2, '🔴');

  const Signal(this.code, this.emoji);
  final int code;
  final String emoji;

  static Signal fromCode(int code) =>
      code == 0 ? Signal.green : (code == 2 ? Signal.red : Signal.yellow);
}

/// 单品营养快照（每 100g + 实际克重）。
class FoodNutrition {
  const FoodNutrition({
    required this.name,
    required this.grams,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    required this.sugarPer100g,
    this.fiberPer100g = 0,
  });

  final String name;
  final int grams;
  final double caloriesPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final double sugarPer100g;
  final double fiberPer100g;

  double get totalCalories => caloriesPer100g * grams / 100;
  double get totalProtein => proteinPer100g * grams / 100;
  double get totalFat => fatPer100g * grams / 100;
  double get totalSugar => sugarPer100g * grams / 100;
}

/// 用户当日上下文。
class DailyContext {
  const DailyContext({
    required this.goalType, // 1减脂 2维持 3增肌
    required this.targetCalories,
    required this.consumedCalories,
    required this.targetProtein,
    required this.consumedProtein,
    this.allergies = const <String>[],
  });

  final int goalType;
  final int targetCalories;
  final double consumedCalories;
  final int targetProtein;
  final double consumedProtein;
  final List<String> allergies;

  double get remainingCalories => targetCalories - consumedCalories;
  double get remainingProtein => targetProtein - consumedProtein;
  bool get isCut => goalType == 1;
}

/// 引擎结果。
class TrafficLightResult {
  const TrafficLightResult({
    required this.signal,
    required this.advice,
    this.suggestedGrams,
  });

  final Signal signal;
  final String advice;
  final int? suggestedGrams;
}

/// 红黄绿灯引擎。纯函数。
class TrafficLightEngine {
  TrafficLightEngine._();

  /// 评估单品。规则优先级自上而下、命中即停。
  static TrafficLightResult evaluate({
    required FoodNutrition food,
    required DailyContext daily,
    double? overrideGreenFatMax,
    double? overrideGreenProteinMin,
    double? overrideGreenBudgetPct,
    double? overrideRedSugarMax,
    double? overrideRedFatMax,
  }) {
    final greenFatMax = overrideGreenFatMax ?? AppConstants.greenLowFatPer100g;
    final greenProteinMin =
        overrideGreenProteinMin ?? AppConstants.greenHighProteinPer100g;
    final greenBudgetPct =
        overrideGreenBudgetPct ?? AppConstants.greenBudgetPctThreshold;
    final redSugarMax = overrideRedSugarMax ?? AppConstants.redHighSugarPer100g;
    final redFatMax = overrideRedFatMax ?? AppConstants.redHighFatPer100g;

    // R1：禁忌/过敏。食物名命中过敏词即红。
    final hit = _hitAllergen(food.name, daily.allergies);
    if (hit != null) {
      return TrafficLightResult(signal: Signal.red, advice: '含你的禁忌食材：$hit');
    }

    // R2：单品热量 > 当日剩余预算 → 红
    final remaining = daily.remainingCalories;
    final itemCal = food.totalCalories;
    if (remaining < 0 || itemCal > remaining) {
      return TrafficLightResult(
        signal: Signal.red,
        advice: '这一份${itemCal.round()}kcal，超过今天剩余的${remaining.round()}kcal预算',
      );
    }

    // R3：减脂 && (糖>20g/100g || 脂肪>20g/100g) → 红
    if (daily.isCut &&
        (food.sugarPer100g > redSugarMax || food.fatPer100g > redFatMax)) {
      final reason = food.sugarPer100g > redSugarMax ? '高糖' : '高脂';
      return TrafficLightResult(
        signal: Signal.red,
        advice: '$reason/高脂，减脂期不建议',
      );
    }

    // R4：高蛋白低脂且预算内 → 绿
    final proteinGap = daily.remainingProtein;
    if (food.proteinPer100g >= greenProteinMin &&
        food.fatPer100g <= greenFatMax &&
        itemCal <= remaining) {
      return TrafficLightResult(
        signal: Signal.green,
        advice: '高蛋白低脂，今天蛋白质还差${proteinGap.round()}g，放心吃',
      );
    }

    // R5：热量 ≤ 剩余预算 30% → 绿
    final pct = remaining > 0 ? itemCal / remaining : 1.0;
    if (pct <= greenBudgetPct) {
      return TrafficLightResult(
        signal: Signal.green,
        advice: '占今日预算${(pct * 100).round()}%，在计划内',
      );
    }

    // R6：其他 → 黄，建议克重
    final suggestedGrams = _suggestGrams(
      food,
      daily,
      remaining,
      greenBudgetPct,
    );
    return TrafficLightResult(
      signal: Signal.yellow,
      advice: '可以吃，注意份量，建议${suggestedGrams}g左右',
      suggestedGrams: suggestedGrams,
    );
  }

  /// 命中过敏词：支持部分匹配（"花生" 命中 "花生米"）。
  static String? _hitAllergen(String foodName, List<String> allergies) {
    for (final a in allergies) {
      if (a.isEmpty) continue;
      if (foodName.contains(a)) return a;
    }
    return null;
  }

  /// 建议克重：让单品热量落到剩余预算的 30% 以内。
  static int _suggestGrams(
    FoodNutrition food,
    DailyContext daily,
    double remaining,
    double pct,
  ) {
    if (food.caloriesPer100g <= 0) return food.grams;
    final targetCal = remaining * pct;
    final g = (targetCal / food.caloriesPer100g * 100).round();
    if (g <= 0) return 50; // 退化兜底
    if (g > 600) return 600; // 上限
    return (g / 50).round() * 50; // 50g 步进
  }
}
