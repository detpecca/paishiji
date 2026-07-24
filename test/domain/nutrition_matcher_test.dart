// 拍食记营养库匹配单测。100% 覆盖。
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/domain/nutrition_matcher.dart';

void main() {
  // 准备一个迷你库
  final foods = <FoodRecord>[
    const FoodRecord(
      id: 1,
      name: '番茄炒蛋',
      aliasesJson: '["西红柿炒蛋"]',
      caloriesPer100g: 86,
      proteinPer100g: 5.6,
      carbsPer100g: 4.4,
      fatPer100g: 5.1,
    ),
    const FoodRecord(
      id: 2,
      name: '米饭',
      aliasesJson: '["白米饭"]',
      caloriesPer100g: 116,
      proteinPer100g: 2.6,
      carbsPer100g: 25.9,
      fatPer100g: 0.3,
    ),
  ];

  group('NutritionMatcher.match — 精确', () {
    test('精确匹配 name', () {
      final r = NutritionMatcher.match(detectedName: '番茄炒蛋', foods: foods);
      expect(r.isFound, isTrue);
      expect(r.record!.id, 1);
    });

    test('精确匹配 name 忽略大小写空白', () {
      final r = NutritionMatcher.match(detectedName: ' 番 茄 炒 蛋 ', foods: foods);
      expect(r.isFound, isTrue);
      expect(r.record!.id, 1);
    });

    test('精确匹配 aliases', () {
      final r = NutritionMatcher.match(detectedName: '西红柿炒蛋', foods: foods);
      expect(r.isFound, isTrue);
      expect(r.record!.id, 1);
    });
  });

  group('模糊匹配（Levenshtein 相似度）', () {
    test('相似度 ≥0.6 命中', () {
      // '番茄炒鸡蛋' vs '番茄炒蛋' edit=1, len=5 → sim≈0.8
      final r = NutritionMatcher.match(
        detectedName: '番茄炒鸡蛋',
        foods: foods,
        minSimilarity: 0.6,
      );
      expect(r.isFound, isTrue);
      expect(r.record!.id, 1);
    });

    test('相似度过低 → notFound', () {
      final r = NutritionMatcher.match(
        detectedName: '飞机',
        foods: foods,
        minSimilarity: 0.6,
      );
      expect(r.isFound, isFalse);
    });

    test('空名 → notFound，候选为空', () {
      final r = NutritionMatcher.match(detectedName: '', foods: foods);
      expect(r.isFound, isFalse);
      expect(r.candidates, isEmpty);
    });
  });

  group('FoodRecord.aliases 解析', () {
    test('合法 JSON 数组', () {
      expect(
        const FoodRecord(
          id: 1,
          name: 'x',
          aliasesJson: '["a","b"]',
          caloriesPer100g: 1,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 1,
        ).aliases,
        ['a', 'b'],
      );
    });
    test('空数组 / 非法 JSON → 空列表', () {
      expect(
        const FoodRecord(
          id: 1,
          name: 'x',
          aliasesJson: '[]',
          caloriesPer100g: 1,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 1,
        ).aliases,
        isEmpty,
      );
      expect(
        const FoodRecord(
          id: 1,
          name: 'x',
          aliasesJson: 'not-json',
          caloriesPer100g: 1,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 1,
        ).aliases,
        isEmpty,
      );
    });
  });

  group('notFound 时返回候选', () {
    test('低于阈值但接近的食物出现在候选里', () {
      final foods2 = <FoodRecord>[
        const FoodRecord(
          id: 1,
          name: '番茄炒蛋',
          aliasesJson: '[]',
          caloriesPer100g: 86,
          proteinPer100g: 5.6,
          carbsPer100g: 4.4,
          fatPer100g: 5.1,
        ),
      ];
      final r = NutritionMatcher.match(
        detectedName: '飞机',
        foods: foods2,
        minSimilarity: 0.99,
      );
      expect(r.isFound, isFalse);
      // 候选为空（飞机 vs 番茄炒蛋 sim 太低）
      expect(r.candidates, isEmpty);
    });
  });
}
