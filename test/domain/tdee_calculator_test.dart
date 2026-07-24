// 拍食记 TDEE 计算引擎单测。纯函数，100% 覆盖。
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/domain/tdee_calculator.dart';

void main() {
  // 固定"现在"以消除年龄漂移。
  final now = DateTime(2026, 7, 24);

  group('TdeeCalculator — DoD 精确用例', () {
    test('男/25/175cm/70kg/减脂/0.5kg每周/轻活动 → 1700~1900kcal、蛋白质 ≥130g', () {
      // age = 2026 - 2001 = 25
      final input = TdeeInput(
        gender: Gender.male,
        birthYear: 2001,
        heightCm: 175,
        weightKg: 70,
        activityLevel: ActivityLevel.light,
        goalType: GoalType.cut,
        goalRate: GoalRate.medium,
        now: now,
      );
      final r = TdeeCalculator.calculate(input);

      // BMR = 10*70 + 6.25*175 - 5*25 + 5 = 1673.75
      expect(r.bmr, closeTo(1673.75, 0.01));
      // TDEE = BMR * 1.375 = 2301.40625
      expect(r.tdee, closeTo(2301.41, 0.01));
      // target = TDEE - 550 = 1751.40625 → 1751
      expect(r.targetCalories, 1751);
      expect(r.targetCalories, inInclusiveRange(1700, 1900));
      // protein = 70 * 2.0 = 140 (减脂)
      expect(r.proteinG, closeTo(140, 0.01));
      expect(r.proteinG, greaterThanOrEqualTo(130));
      // fat = 1751 * 0.25 / 9 ≈ 48.64
      expect(r.fatG, closeTo(48.64, 0.01));
      // carbs = (1751 - 140*4 - 48.64*9) / 4 ≈ 188.31（脂肪用四舍后的 48.64，略偏）
      expect(r.carbsG, closeTo(188.31, 0.1));
    });
  });

  group('BMR（Mifflin-St Jeor）', () {
    test('男 = 10×W + 6.25×H − 5×age + 5', () {
      final r = TdeeCalculator.bmr(
        TdeeInput(
          gender: Gender.male,
          birthYear: 2001,
          heightCm: 175,
          weightKg: 70,
          activityLevel: ActivityLevel.sedentary,
          goalType: GoalType.maintain,
          goalRate: GoalRate.slow,
          now: now,
        ),
      );
      expect(r, closeTo(1673.75, 0.01));
    });

    test('女 = 10×W + 6.25×H − 5×age − 161', () {
      // 女 1996 生 / 30 岁 / 165 / 60
      final r = TdeeCalculator.bmr(
        TdeeInput(
          gender: Gender.female,
          birthYear: 1996,
          heightCm: 165,
          weightKg: 60,
          activityLevel: ActivityLevel.sedentary,
          goalType: GoalType.maintain,
          goalRate: GoalRate.slow,
          now: now,
        ),
      );
      // 10*60 + 6.25*165 - 5*30 - 161 = 600 + 1031.25 - 150 - 161 = 1320.25
      expect(r, closeTo(1320.25, 0.01));
    });
  });

  group('活动系数 1.2/1.375/1.55/1.725/1.9', () {
    final base = TdeeInput(
      gender: Gender.male,
      birthYear: 2001,
      heightCm: 175,
      weightKg: 70,
      activityLevel: ActivityLevel.sedentary,
      goalType: GoalType.maintain,
      goalRate: GoalRate.slow,
      now: now,
    );
    final levels = [
      (ActivityLevel.sedentary, 1.2),
      (ActivityLevel.light, 1.375),
      (ActivityLevel.moderate, 1.55),
      (ActivityLevel.active, 1.725),
      (ActivityLevel.veryActive, 1.9),
    ];
    for (final (level, factor) in levels) {
      test('$level 系数 = $factor', () {
        final tdee = TdeeCalculator.maintenance(
          TdeeInput(
            gender: base.gender,
            birthYear: base.birthYear,
            heightCm: base.heightCm,
            weightKg: base.weightKg,
            activityLevel: level,
            goalType: base.goalType,
            goalRate: base.goalRate,
            now: base.now,
          ),
        );
        expect(tdee, closeTo(1673.75 * factor, 0.01));
      });
    }
  });

  group('目标调整', () {
    final input = TdeeInput(
      gender: Gender.male,
      birthYear: 2001,
      heightCm: 175,
      weightKg: 70,
      activityLevel: ActivityLevel.light,
      goalType: GoalType.cut,
      goalRate: GoalRate.medium,
      now: now,
    );
    final maint = TdeeCalculator.maintenance(input); // 2301.40625

    test('减脂按速率减 275/550/825', () {
      final slow = TdeeCalculator.targetCalories(
        TdeeInput(
          gender: input.gender,
          birthYear: input.birthYear,
          heightCm: input.heightCm,
          weightKg: input.weightKg,
          activityLevel: input.activityLevel,
          goalType: GoalType.cut,
          goalRate: GoalRate.slow,
          now: now,
        ),
      );
      expect(slow, (maint - 275).round());

      final medium = TdeeCalculator.targetCalories(
        TdeeInput(
          gender: input.gender,
          birthYear: input.birthYear,
          heightCm: input.heightCm,
          weightKg: input.weightKg,
          activityLevel: input.activityLevel,
          goalType: GoalType.cut,
          goalRate: GoalRate.medium,
          now: now,
        ),
      );
      expect(medium, (maint - 550).round());

      final fast = TdeeCalculator.targetCalories(
        TdeeInput(
          gender: input.gender,
          birthYear: input.birthYear,
          heightCm: input.heightCm,
          weightKg: input.weightKg,
          activityLevel: input.activityLevel,
          goalType: GoalType.cut,
          goalRate: GoalRate.fast,
          now: now,
        ),
      );
      expect(fast, (maint - 825).round());
    });

    test('增肌 +300 kcal/日，与速率无关', () {
      for (final rate in GoalRate.values) {
        final t = TdeeCalculator.targetCalories(
          TdeeInput(
            gender: input.gender,
            birthYear: input.birthYear,
            heightCm: input.heightCm,
            weightKg: input.weightKg,
            activityLevel: input.activityLevel,
            goalType: GoalType.gain,
            goalRate: rate,
            now: now,
          ),
        );
        expect(t, (maint + 300).round(), reason: 'rate=$rate');
      }
    });

    test('维持 = maintenance，与速率无关', () {
      for (final rate in GoalRate.values) {
        final t = TdeeCalculator.targetCalories(
          TdeeInput(
            gender: input.gender,
            birthYear: input.birthYear,
            heightCm: input.heightCm,
            weightKg: input.weightKg,
            activityLevel: input.activityLevel,
            goalType: GoalType.maintain,
            goalRate: rate,
            now: now,
          ),
        );
        expect(t, maint.round(), reason: 'rate=$rate');
      }
    });
  });

  group('宏量分配', () {
    test('减脂蛋白质 2.0 g/kg', () {
      final p = TdeeCalculator.proteinGrams(
        TdeeInput(
          gender: Gender.male,
          birthYear: 2001,
          heightCm: 175,
          weightKg: 70,
          activityLevel: ActivityLevel.light,
          goalType: GoalType.cut,
          goalRate: GoalRate.medium,
          now: now,
        ),
      );
      expect(p, closeTo(140, 0.01));
    });

    test('维持/增肌蛋白质 1.8 g/kg', () {
      for (final g in [GoalType.maintain, GoalType.gain]) {
        final p = TdeeCalculator.proteinGrams(
          TdeeInput(
            gender: Gender.male,
            birthYear: 2001,
            heightCm: 175,
            weightKg: 70,
            activityLevel: ActivityLevel.light,
            goalType: g,
            goalRate: GoalRate.medium,
            now: now,
          ),
        );
        expect(p, closeTo(126, 0.01), reason: 'goal=$g');
      }
    });

    test('脂肪占总热量 25%', () {
      expect(TdeeCalculator.fatGrams(2000), closeTo(2000 * 0.25 / 9, 0.01));
      expect(TdeeCalculator.fatGrams(1751), closeTo(1751 * 0.25 / 9, 0.01));
    });

    test('碳水 = (总热量 − 蛋白×4 − 脂肪×9) / 4，结果非负', () {
      final c = TdeeCalculator.carbsGrams(
        targetCalories: 1751,
        proteinG: 140,
        fatG: 48.64,
      );
      expect(c, closeTo((1751 - 140 * 4 - 48.64 * 9) / 4, 0.01));
      expect(c, greaterThanOrEqualTo(0));
    });

    test('热量守恒：蛋白×4 + 脂肪×9 + 碳水×4 ≈ 目标热量', () {
      final r = TdeeCalculator.calculate(
        TdeeInput(
          gender: Gender.female,
          birthYear: 1996,
          heightCm: 165,
          weightKg: 60,
          activityLevel: ActivityLevel.moderate,
          goalType: GoalType.gain,
          goalRate: GoalRate.fast,
          now: now,
        ),
      );
      final reconstructed = r.proteinG * 4 + r.fatG * 9 + r.carbsG * 4;
      expect(reconstructed, closeTo(r.targetCalories, 1.0));
    });
  });

  group('枚举 fromCode 双向', () {
    test('Gender/GoalType/GoalRate/ActivityLevel fromCode 对称', () {
      for (final g in Gender.values) {
        expect(Gender.fromCode(g.code), g);
      }
      for (final g in GoalType.values) {
        expect(GoalType.fromCode(g.code), g);
      }
      for (final r in GoalRate.values) {
        expect(GoalRate.fromCode(r.code), r);
      }
      for (final a in ActivityLevel.values) {
        expect(ActivityLevel.fromCode(a.code), a);
      }
    });
  });
}
