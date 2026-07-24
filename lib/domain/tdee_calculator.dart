// 拍食记 TDEE 计算引擎。CLAUDE.md §5.3。
//
// 公式：
// - BMR (Mifflin-St Jeor)：
//     男 = 10×体重(kg) + 6.25×身高(cm) − 5×年龄 + 5
//     女 = 10×体重(kg) + 6.25×身高(cm) − 5×年龄 − 161
// - TDEE = BMR × 活动系数 (1.2/1.375/1.55/1.725/1.9)
// - 目标调整：减脂按速率减 275/550/825 kcal/日；增肌加 300 kcal/日；维持不变
// - 蛋白质：减脂 2.0 g/kg；其他 1.8 g/kg
// - 脂肪：占总热量 25%
// - 碳水：剩余热量 ÷ 4
//
// 纯 Dart，不 import Flutter；100% 单测覆盖。阈值集中在 AppConstants。

import '../core/constants.dart';

/// 性别枚举（对应 profile.gender：1男 2女）。
enum Gender {
  male(1),
  female(2);

  const Gender(this.code);
  final int code;

  static Gender fromCode(int code) => code == 2 ? Gender.female : Gender.male;
}

/// 目标类型（对应 profile.goal_type：1减脂 2维持 3增肌）。
enum GoalType {
  cut(1),
  maintain(2),
  gain(3);

  const GoalType(this.code);
  final int code;

  static GoalType fromCode(int code) {
    if (code == 3) return GoalType.gain;
    if (code == 2) return GoalType.maintain;
    return GoalType.cut;
  }
}

/// 减脂/增肌速率档（对应 profile.goal_rate：1=0.25kg 2=0.5kg 3=0.75kg 每周）。
enum GoalRate {
  slow(1, 275),
  medium(2, 550),
  fast(3, 825);

  const GoalRate(this.code, this.kcalPerWeek);
  final int code;
  final int kcalPerWeek; // 每周总赤字，摊到每日即同一数值（CLAUDE.md 文本：减 275/550/825 kcal/日）

  static GoalRate fromCode(int code) {
    if (code == 3) return GoalRate.fast;
    if (code == 2) return GoalRate.medium;
    return GoalRate.slow;
  }
}

/// 活动量档（对应 profile.activity_level：1久坐~5重体力）。
enum ActivityLevel {
  sedentary(1),
  light(2),
  moderate(3),
  active(4),
  veryActive(5);

  const ActivityLevel(this.code);
  final int code;

  static ActivityLevel fromCode(int code) {
    if (code == 5) return ActivityLevel.veryActive;
    if (code == 4) return ActivityLevel.active;
    if (code == 3) return ActivityLevel.moderate;
    if (code == 2) return ActivityLevel.light;
    return ActivityLevel.sedentary;
  }

  /// 活动系数，下标 = code-1。
  double get factor => AppConstants.activityFactors[code - 1];
}

/// TDEE 计算入参。onboarding/设置页构造后传入。
class TdeeInput {
  const TdeeInput({
    required this.gender,
    required this.birthYear,
    required this.heightCm,
    required this.weightKg,
    required this.activityLevel,
    required this.goalType,
    required this.goalRate,
    required this.now,
  });

  final Gender gender;
  final int birthYear;
  final double heightCm;
  final double weightKg;
  final ActivityLevel activityLevel;
  final GoalType goalType;
  final GoalRate goalRate;
  final DateTime now;

  int ageAt(DateTime now) => now.year - birthYear;
}

/// TDEE 计算结果。落到 profile 的 targetCalories/protein_g/carbs_g/fat_g。
class TdeeResult {
  const TdeeResult({
    required this.bmr,
    required this.tdee,
    required this.targetCalories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  final double bmr;
  final double tdee;
  final int targetCalories;
  final double proteinG;
  final double carbsG;
  final double fatG;
}

/// 纯函数 TDEE 计算器。无副作用、可单测。
class TdeeCalculator {
  TdeeCalculator._();

  /// BMR（Mifflin-St Jeor）。
  static double bmr(TdeeInput input) {
    final weight = input.weightKg;
    final height = input.heightCm;
    final age = input.ageAt(input.now);
    final base = 10 * weight + 6.25 * height - 5 * age;
    return input.gender == Gender.male ? base + 5 : base - 161;
  }

  /// 维持热量（BMR × 活动系数）。
  static double maintenance(TdeeInput input) =>
      bmr(input) * input.activityLevel.factor;

  /// 目标每日热量（减脂减赤字、增肌加盈余、维持不变）。
  static int targetCalories(TdeeInput input) {
    final maint = maintenance(input);
    final double adjusted;
    switch (input.goalType) {
      case GoalType.cut:
        adjusted = maint - input.goalRate.kcalPerWeek;
        break;
      case GoalType.gain:
        adjusted = maint + AppConstants.surplusKcalForGain;
        break;
      case GoalType.maintain:
        adjusted = maint;
        break;
    }
    return adjusted.round();
  }

  /// 蛋白质（g）：减脂 2.0 g/kg；其他 1.8 g/kg。
  static double proteinGrams(TdeeInput input) {
    final perKg = input.goalType == GoalType.cut
        ? AppConstants.proteinPerKgCut
        : AppConstants.proteinPerKgOther;
    return input.weightKg * perKg;
  }

  /// 脂肪（g）：占总热量 25%，÷9。
  static double fatGrams(int targetCalories) =>
      targetCalories * AppConstants.fatShareOfCalories / 9;

  /// 碳水（g）：总热量 − 蛋白质热量 − 脂肪热量，÷4。
  static double carbsGrams({
    required int targetCalories,
    required double proteinG,
    required double fatG,
  }) {
    final proteinKcal = proteinG * 4;
    final fatKcal = fatG * 9;
    final carbsKcal = targetCalories - proteinKcal - fatKcal;
    return carbsKcal / 4;
  }

  /// 一次算全。落库用此返回的四个值。
  static TdeeResult calculate(TdeeInput input) {
    final bmrVal = bmr(input);
    final tdee = maintenance(input);
    final target = targetCalories(input);
    final protein = proteinGrams(input);
    final fat = fatGrams(target);
    final carbs = carbsGrams(
      targetCalories: target,
      proteinG: protein,
      fatG: fat,
    );
    return TdeeResult(
      bmr: bmrVal,
      tdee: tdee,
      targetCalories: target,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
    );
  }
}
