// 拍食记 onboarding 状态。Riverpod 持有，6 屏共享、可回退编辑。
import 'package:flutter/material.dart';
import 'package:paishiji/domain/tdee_calculator.dart';

/// onboarding 每一步收集的草稿。提交时落 profile。
@immutable
class OnboardingDraft {
  const OnboardingDraft({
    this.gender,
    this.birthYear,
    this.heightCm = 170.0,
    this.weightKg = 65.0,
    this.activityLevel = ActivityLevel.light,
    this.goalType = GoalType.cut,
    this.goalRate = GoalRate.medium,
    this.targetCalories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.allergies = const <String>[],
  });

  final Gender? gender;
  final int? birthYear;
  final double heightCm;
  final double weightKg;
  final ActivityLevel activityLevel;
  final GoalType goalType;
  final GoalRate goalRate;
  final int? targetCalories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final List<String> allergies;

  bool get step1Valid => gender != null && birthYear != null;
  bool get step2Valid => heightCm > 0 && weightKg > 0;
  bool get canFinish => step1Valid && step2Valid;

  /// 草稿是否被手改过目标宏量（用于"修改后不再自动覆盖"判断）。
  bool get targetsOverridden =>
      targetCalories != null ||
      proteinG != null ||
      carbsG != null ||
      fatG != null;

  OnboardingDraft copyWith({
    Gender? gender,
    int? birthYear,
    double? heightCm,
    double? weightKg,
    ActivityLevel? activityLevel,
    GoalType? goalType,
    GoalRate? goalRate,
    int? targetCalories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    List<String>? allergies,
  }) => OnboardingDraft(
    gender: gender ?? this.gender,
    birthYear: birthYear ?? this.birthYear,
    heightCm: heightCm ?? this.heightCm,
    weightKg: weightKg ?? this.weightKg,
    activityLevel: activityLevel ?? this.activityLevel,
    goalType: goalType ?? this.goalType,
    goalRate: goalRate ?? this.goalRate,
    targetCalories: targetCalories ?? this.targetCalories,
    proteinG: proteinG ?? this.proteinG,
    carbsG: carbsG ?? this.carbsG,
    fatG: fatG ?? this.fatG,
    allergies: allergies ?? this.allergies,
  );

  /// 计算 TDEE；若用户手改过则尊重手改值（CLAUDE.md §5.3）。
  TdeeResult resolveTargets(DateTime now) {
    final computed = TdeeCalculator.calculate(
      TdeeInput(
        gender: gender!,
        birthYear: birthYear!,
        heightCm: heightCm,
        weightKg: weightKg,
        activityLevel: activityLevel,
        goalType: goalType,
        goalRate: goalRate,
        now: now,
      ),
    );
    if (!targetsOverridden) return computed;
    return TdeeResult(
      bmr: computed.bmr,
      tdee: computed.tdee,
      targetCalories: targetCalories ?? computed.targetCalories,
      proteinG: proteinG ?? computed.proteinG,
      carbsG: carbsG ?? computed.carbsG,
      fatG: fatG ?? computed.fatG,
    );
  }
}

/// onboarding 6 屏索引。0=性别年龄 1=身高体重 2=目标 3=速率 4=活动量 5=结果确认。
class OnboardingController extends ValueNotifier<OnboardingDraft> {
  OnboardingController() : super(const OnboardingDraft());

  int page = 0;

  void setGender(Gender g) => value = value.copyWith(gender: g);
  void setBirthYear(int year) => value = value.copyWith(birthYear: year);
  void setHeightCm(double h) => value = value.copyWith(heightCm: h);
  void setWeightKg(double w) => value = value.copyWith(weightKg: w);
  void setGoalType(GoalType g) => value = value.copyWith(goalType: g);
  void setGoalRate(GoalRate r) => value = value.copyWith(goalRate: r);
  void setActivityLevel(ActivityLevel a) =>
      value = value.copyWith(activityLevel: a);
  void setAllergies(List<String> a) => value = value.copyWith(allergies: a);

  /// 用户在结果页手改目标。触发"不再自动覆盖"标志。
  void overrideTargetCalories(int v) =>
      value = value.copyWith(targetCalories: v);
  void overrideProtein(double v) => value = value.copyWith(proteinG: v);
  void overrideCarbs(double v) => value = value.copyWith(carbsG: v);
  void overrideFat(double v) => value = value.copyWith(fatG: v);
}
