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

  /// 新增一条（返回自增 id）。
  Future<int> addOne(FoodsCompanion entry) => into(foods).insert(entry);

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
