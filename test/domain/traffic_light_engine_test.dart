// 拍食记红黄绿灯引擎单测。100% 覆盖，含优先级冲突。
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/domain/traffic_light_engine.dart';

void main() {
  const baseFood = FoodNutrition(
    name: '鸡胸肉',
    grams: 100,
    caloriesPer100g: 133,
    proteinPer100g: 31,
    carbsPer100g: 0,
    fatPer100g: 1.2,
    sugarPer100g: 0,
  );

  const baseDaily = DailyContext(
    goalType: 1, // 减脂
    targetCalories: 1751,
    consumedCalories: 0,
    targetProtein: 140,
    consumedProtein: 0,
  );

  group('R1 禁忌/过敏（优先级最高）', () {
    test('食物名含过敏词 → 红', () {
      const daily = DailyContext(
        goalType: 1,
        targetCalories: 2000,
        consumedCalories: 0,
        targetProtein: 140,
        consumedProtein: 0,
        allergies: ['花生'],
      );
      const food = FoodNutrition(
        name: '宫保鸡丁花生碎',
        grams: 200,
        caloriesPer100g: 165,
        proteinPer100g: 12,
        carbsPer100g: 8,
        fatPer100g: 10,
        sugarPer100g: 3,
      );
      final r = TrafficLightEngine.evaluate(food: food, daily: daily);
      expect(r.signal, Signal.red);
      expect(r.advice, contains('花生'));
    });
  });

  group('R2 超预算', () {
    test('单品热量 > 剩余预算 → 红', () {
      const food = FoodNutrition(
        name: '红烧肉',
        grams: 300,
        caloriesPer100g: 250,
        proteinPer100g: 14,
        carbsPer100g: 8,
        fatPer100g: 20,
        sugarPer100g: 6,
      );
      const daily = DailyContext(
        goalType: 1,
        targetCalories: 1751,
        consumedCalories: 1700, // 剩余 51
        targetProtein: 140,
        consumedProtein: 0,
      );
      final r = TrafficLightEngine.evaluate(food: food, daily: daily);
      expect(r.signal, Signal.red);
      expect(r.advice, contains('超过今天剩余'));
    });

    test('剩余预算 <0 时也红', () {
      const daily = DailyContext(
        goalType: 1,
        targetCalories: 1751,
        consumedCalories: 2000, // 已超
        targetProtein: 140,
        consumedProtein: 0,
      );
      final r = TrafficLightEngine.evaluate(food: baseFood, daily: daily);
      expect(r.signal, Signal.red);
    });
  });

  group('R3 减脂高糖/高脂', () {
    test('减脂 + 脂肪>20g/100g → 红', () {
      const food = FoodNutrition(
        name: '红烧肉',
        grams: 100,
        caloriesPer100g: 250,
        proteinPer100g: 14,
        carbsPer100g: 8,
        fatPer100g: 21,
        sugarPer100g: 6,
      );
      final r = TrafficLightEngine.evaluate(food: food, daily: baseDaily);
      expect(r.signal, Signal.red);
      expect(r.advice, contains('高脂'));
    });

    test('减脂 + 糖>20g/100g → 红', () {
      const food = FoodNutrition(
        name: '蛋糕',
        grams: 100,
        caloriesPer100g: 350,
        proteinPer100g: 5,
        carbsPer100g: 50,
        fatPer100g: 10,
        sugarPer100g: 25,
      );
      final r = TrafficLightEngine.evaluate(food: food, daily: baseDaily);
      expect(r.signal, Signal.red);
    });

    test('维持目标不走 R3（即便高脂）', () {
      const food = FoodNutrition(
        name: '红烧肉',
        grams: 100,
        caloriesPer100g: 250,
        proteinPer100g: 14,
        carbsPer100g: 8,
        fatPer100g: 21,
        sugarPer100g: 6,
      );
      const daily = DailyContext(
        goalType: 2, // 维持
        targetCalories: 2000,
        consumedCalories: 0,
        targetProtein: 140,
        consumedProtein: 0,
      );
      final r = TrafficLightEngine.evaluate(food: food, daily: daily);
      expect(r.signal, isNot(Signal.red));
    });
  });

  group('R4 高蛋白低脂', () {
    test('蛋白质≥15 && 脂肪≤10 && 预算内 → 绿', () {
      final r = TrafficLightEngine.evaluate(food: baseFood, daily: baseDaily);
      expect(r.signal, Signal.green);
      expect(r.advice, contains('高蛋白低脂'));
      expect(r.advice, contains('蛋白质还差'));
    });

    test('脂肪 >10 不触发 R4（走 R6 黄）', () {
      // 鸡腿肉 400g：脂肪 13>10 跳过 R4；热量 724/1751≈41%>30% 跳过 R5
      const food = FoodNutrition(
        name: '鸡腿肉',
        grams: 400,
        caloriesPer100g: 181,
        proteinPer100g: 20,
        carbsPer100g: 0,
        fatPer100g: 13,
        sugarPer100g: 0,
      );
      final r = TrafficLightEngine.evaluate(food: food, daily: baseDaily);
      expect(r.signal, Signal.yellow);
    });
  });

  group('R5 ≤ 剩余预算 30% → 绿', () {
    test('小份量在计划内 → 绿', () {
      const food = FoodNutrition(
        name: '黄瓜',
        grams: 100,
        caloriesPer100g: 16,
        proteinPer100g: 0.8,
        carbsPer100g: 2.9,
        fatPer100g: 0.2,
        sugarPer100g: 2.2,
      );
      final r = TrafficLightEngine.evaluate(food: food, daily: baseDaily);
      expect(r.signal, Signal.green);
      expect(r.advice, contains('占今日预算'));
    });
  });

  group('R6 其他 → 黄', () {
    test('中热量但非高蛋白低脂 → 黄，带建议克重', () {
      // 馒头 300g：蛋白 7<15 不触发 R4；热量 669/1751≈38%>30% 不触发 R5
      const food = FoodNutrition(
        name: '馒头',
        grams: 300,
        caloriesPer100g: 223,
        proteinPer100g: 7,
        carbsPer100g: 47,
        fatPer100g: 1.1,
        sugarPer100g: 1.1,
      );
      final r = TrafficLightEngine.evaluate(food: food, daily: baseDaily);
      expect(r.signal, Signal.yellow);
      expect(r.advice, contains('注意份量'));
      expect(r.suggestedGrams, isNotNull);
    });
  });

  group('优先级冲突', () {
    test('R1（过敏）优先于 R4（高蛋白低脂）', () {
      const food = FoodNutrition(
        name: '花生鸡胸',
        grams: 100,
        caloriesPer100g: 200,
        proteinPer100g: 30,
        carbsPer100g: 5,
        fatPer100g: 5,
        sugarPer100g: 0,
      );
      const daily = DailyContext(
        goalType: 1,
        targetCalories: 2000,
        consumedCalories: 0,
        targetProtein: 140,
        consumedProtein: 0,
        allergies: ['花生'],
      );
      final r = TrafficLightEngine.evaluate(food: food, daily: daily);
      expect(r.signal, Signal.red);
      expect(r.advice, contains('花生'));
    });

    test('R2（超预算）优先于 R4', () {
      const food = FoodNutrition(
        name: '鸡胸肉',
        grams: 2000, // 超大份，超预算
        caloriesPer100g: 133,
        proteinPer100g: 31,
        carbsPer100g: 0,
        fatPer100g: 1.2,
        sugarPer100g: 0,
      );
      const daily = DailyContext(
        goalType: 1,
        targetCalories: 1751,
        consumedCalories: 0,
        targetProtein: 140,
        consumedProtein: 0,
      );
      final r = TrafficLightEngine.evaluate(food: food, daily: daily);
      expect(r.signal, Signal.red);
      expect(r.advice, contains('超过今天剩余'));
    });

    test('R3（高脂）优先于 R5（计划内）', () {
      // 一份小量高脂：即便热量占预算 <30%，减脂仍判红
      const food = FoodNutrition(
        name: '黄油',
        grams: 20,
        caloriesPer100g: 717,
        proteinPer100g: 0.5,
        carbsPer100g: 0.1,
        fatPer100g: 81,
        sugarPer100g: 0.1,
      );
      const daily = DailyContext(
        goalType: 1,
        targetCalories: 2000,
        consumedCalories: 0,
        targetProtein: 140,
        consumedProtein: 0,
      );
      final r = TrafficLightEngine.evaluate(food: food, daily: daily);
      // 143kcal 占 2000 的 7% < 30%，但脂肪 81>20 → R3 命中
      expect(r.signal, Signal.red);
    });
  });

  group('Signal.fromCode 双向', () {
    test('0→green 1→yellow 2→red', () {
      expect(Signal.fromCode(0), Signal.green);
      expect(Signal.fromCode(1), Signal.yellow);
      expect(Signal.fromCode(2), Signal.red);
      expect(Signal.fromCode(99), Signal.yellow); // 兜底
    });
  });
}
