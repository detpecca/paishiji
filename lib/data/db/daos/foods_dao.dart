// 拍食记食物 DAO。CLAUDE.md §六 Task 7：条码补录 + 未命中入库。
import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

// 食物库 DAO。支持按名/别名/条码命中、批量种子导入、待确认列表。
part 'foods_dao.g.dart';

@DriftAccessor(tables: [Foods])
class FoodsDao extends DatabaseAccessor<AppDatabase> with _$FoodsDaoMixin {
  FoodsDao(super.db);

  Future<List<Food>> all() => select(foods).get();
  Future<Food?> findById(int id) =>
      (select(foods)..where((t) => t.id.equals(id))).getSingleOrNull();
  Future<Food?> findByName(String name) =>
      (select(foods)..where((t) => t.name.equals(name))).getSingleOrNull();
  Future<Food?> findByBarcode(String barcode) => (select(
    foods,
  )..where((t) => t.barcode.equals(barcode))).getSingleOrNull();

  /// 模糊匹配（相似度由调用方计算后传入 name 关键字，DAO 只做名字/别名 LIKE）。
  Future<List<Food>> searchByNameOrAlias(String keyword) {
    final like = '%$keyword%';
    return (select(
      foods,
    )..where((t) => t.name.like(like) | t.aliases.like(like))).get();
  }

  /// 待确认食物（source=2 AI 估算且未验证）。
  Future<List<Food>> pendingVerification() => (select(
    foods,
  )..where((t) => t.source.equals(2) & t.verified.equals(0))).get();

  /// 新增一条（返回自增 id）。barcode 冲突时由 UNIQUE 约束兜底。
  Future<int> addOne(FoodsCompanion entry) => into(foods).insert(entry);

  /// 备份恢复：指定 id 插入（restore 用，保留原 id 避免外键断裂）。
  Future<void> restore(FoodsCompanion entry) =>
      into(foods).insert(entry, mode: InsertMode.insertOrReplace);

  /// 备份恢复：清空 foods（导入前调用，按外键反向删）。
  Future<int> deleteAll() => foods.delete().go();

  /// 按 barcode 插入或覆盖（条码补录：source=3，verified=0）。
  /// 已有同 barcode 的记录则更新营养；否则插入。
  Future<int> upsertByBarcode(FoodsCompanion entry) async {
    final barcode = entry.barcode.value;
    final existing = barcode == null ? null : await findByBarcode(barcode);
    if (existing != null) {
      await (foods.update()..where((t) => t.id.equals(existing.id))).write(
        FoodsCompanion(
          name: entry.name.present ? entry.name : const Value.absent(),
          caloriesPer100g: entry.caloriesPer100g.present
              ? entry.caloriesPer100g
              : const Value.absent(),
          proteinPer100g: entry.proteinPer100g.present
              ? entry.proteinPer100g
              : const Value.absent(),
          carbsPer100g: entry.carbsPer100g.present
              ? entry.carbsPer100g
              : const Value.absent(),
          fatPer100g: entry.fatPer100g.present
              ? entry.fatPer100g
              : const Value.absent(),
          sugarPer100g: entry.sugarPer100g.present
              ? entry.sugarPer100g
              : const Value.absent(),
          fiberPer100g: entry.fiberPer100g.present
              ? entry.fiberPer100g
              : const Value.absent(),
          sodiumPer100g: entry.sodiumPer100g.present
              ? entry.sodiumPer100g
              : const Value.absent(),
          source: entry.source.present ? entry.source : const Value.absent(),
          verified: const Value(0),
        ),
      );
      return existing.id;
    }
    return into(foods).insert(entry);
  }

  /// 种子导入：按 name 唯一，已存在跳过（差量合并，不覆盖用户修改）。
  Future<void> upsertSeed(List<FoodsCompanion> entries) => batch(
    (b) => b.insertAll(foods, entries, mode: InsertMode.insertOrIgnore),
  );

  /// 标记验证。
  Future<void> markVerified(int id) =>
      (foods.update()..where((t) => t.id.equals(id))).write(
        const FoodsCompanion(verified: Value(1)),
      );
}
