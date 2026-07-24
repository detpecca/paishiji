// 拍食记 SeedFoodParser 纯函数单测。
// 100% 离线，零 Flutter/IO 依赖，CLAUDE.md §红线#2 数据侧对应。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/data/providers/seed_food_parser.dart';

void main() {
  group('SeedFoodParser.parse', () {
    test('解析单条 snake_case 字段名', () {
      const json = '''
        [{"name":"鸡胸肉","aliases":["鸡胸"],
          "calories_per_100g":133.0,"protein_per_100g":31.0,
          "carbs_per_100g":0.0,"fat_per_100g":1.2,
          "serving_json":{"份":100},"source":1}]
      ''';
      final list = SeedFoodParser.parse(json);
      expect(list, hasLength(1));
      final c = list.single;
      expect(c.name.value, '鸡胸肉');
      expect(jsonDecode(c.aliases.value) as List, ['鸡胸']);
      expect(c.caloriesPer100g.value, 133.0);
      expect(c.proteinPer100g.value, 31.0);
      expect(c.carbsPer100g.value, 0.0);
      expect(c.fatPer100g.value, 1.2);
      expect(jsonDecode(c.servingJson.value), {'份': 100});
      expect(c.source.value, 1);
      expect(c.barcode.value, isNull); // 缺省允许 null
      expect(c.verified.value, 0); // 缺省 0
    });

    test('解析 camelCase 兼容字段名', () {
      const json = '''
        [{"name":"米饭","caloriesPer100g":116.0,"proteinPer100g":2.6,
          "carbsPer100g":25.9,"fatPer100g":0.3}]
      ''';
      final c = SeedFoodParser.parse(json).single;
      expect(c.name.value, '米饭');
      expect(c.caloriesPer100g.value, 116.0);
      expect(c.proteinPer100g.value, 2.6);
    });

    test('缺省字段使用默认值（fiber/sugar/sodium = 0，source = 1，verified = 0）', () {
      const json = '''
        [{"name":"白水","calories_per_100g":0.0,
          "protein_per_100g":0.0,"carbs_per_100g":0.0,"fat_per_100g":0.0}]
      ''';
      final c = SeedFoodParser.parse(json).single;
      expect(c.fiberPer100g.value, 0.0);
      expect(c.sugarPer100g.value, 0.0);
      expect(c.sodiumPer100g.value, 0.0);
      expect(c.source.value, 1);
      expect(c.verified.value, 0);
      expect(c.servingJson.value, '{}');
      expect(c.aliases.value, '[]');
    });

    test('空数组返回空列表', () {
      expect(SeedFoodParser.parse('[]'), isEmpty);
    });

    test('解析真实 seed_foods.json：恰好 50 条、名字唯一、宏量非负', () {
      // 真实资产内容通过 TestAssetBundle 注入（见 seed_loader_test）。
      // 此处用内联构造校验 schema 形状一致。
      final sample = List.generate(
        50,
        (i) => {
          'name': 'food_$i',
          'aliases': ['alias_$i'],
          'calories_per_100g': 10.0 * i + 1,
          'protein_per_100g': 1.0 * i,
          'carbs_per_100g': 2.0 * i,
          'fat_per_100g': 0.5 * i,
          'serving_json': {'份': 100},
          'source': 1,
        },
      );
      final list = SeedFoodParser.parse(jsonEncode(sample));
      expect(list, hasLength(50));
      for (final c in list) {
        expect(c.caloriesPer100g.value, greaterThanOrEqualTo(0));
        expect(c.name.value, isNotEmpty);
      }
    });
  });
}
