import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

// KV DAO：设置项、缓存、种子导入标志、本月识别计数等。
part 'kv_dao.g.dart';

@DriftAccessor(tables: [Kv])
class KvDao extends DatabaseAccessor<AppDatabase> with _$KvDaoMixin {
  KvDao(super.db);

  Future<String?> get(String key) async {
    final row = await (select(
      kv,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String? value) => into(
    kv,
  ).insertOnConflictUpdate(KvCompanion(key: Value(key), value: Value(value)));

  Future<int> remove(String key) =>
      (kv.delete()..where((t) => t.key.equals(key))).go();

  /// 备份恢复：全量读取 + 清空。
  Future<List<KvData>> all() => select(kv).get();
  Future<int> deleteAll() => kv.delete().go();
}
