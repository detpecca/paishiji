import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/database.dart';

/// 把 assets/seed_foods.json 解析为 [FoodsCompanion] 列表。
/// 纯函数，零 IO，100% 单测覆盖（CLAUDE.md §红线#2 的数据侧对应）。
class SeedFoodParser {
  SeedFoodParser._();

  static List<FoodsCompanion> parse(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    return list.map(_toCompanion).toList();
  }

  static FoodsCompanion _toCompanion(dynamic raw) {
    final m = raw as Map<String, dynamic>;
    final aliases = (m['aliases'] ?? const <Object>[]) as List;
    final servingJson = m['serving_json'] ?? m['servingJson'];
    return FoodsCompanion(
      name: Value(m['name'] as String),
      aliases: Value(jsonEncode(aliases)),
      caloriesPer100g: Value(
        ((m['calories_per_100g'] ?? m['caloriesPer100g']) as num).toDouble(),
      ),
      proteinPer100g: Value(
        ((m['protein_per_100g'] ?? m['proteinPer100g']) as num).toDouble(),
      ),
      carbsPer100g: Value(
        ((m['carbs_per_100g'] ?? m['carbsPer100g']) as num).toDouble(),
      ),
      fatPer100g: Value(
        ((m['fat_per_100g'] ?? m['fatPer100g']) as num).toDouble(),
      ),
      fiberPer100g: Value(((m['fiber_per_100g'] ?? 0) as num).toDouble()),
      sugarPer100g: Value(((m['sugar_per_100g'] ?? 0) as num).toDouble()),
      sodiumPer100g: Value(((m['sodium_per_100g'] ?? 0) as num).toDouble()),
      servingJson: Value(servingJson == null ? '{}' : jsonEncode(servingJson)),
      source: Value((m['source'] ?? 1) as int),
      barcode: Value(m['barcode'] as String?),
      verified: Value((m['verified'] ?? 0) as int),
    );
  }
}
