import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'daos/foods_dao.dart';
import 'daos/kv_dao.dart';
import 'daos/meal_entries_dao.dart';
import 'daos/profile_dao.dart';
import 'daos/recognitions_dao.dart';
import 'tables.dart';

// 拍食记 Drift 数据库。表与 DAO 由 build_runner 生成到 database.g.dart。
// 红线#4：所有表含 created_at（见 tables.dart）。

part 'database.g.dart';

@DriftDatabase(
  tables: [Profiles, Foods, Recognitions, RecognitionItems, MealEntries, Kv],
  daos: [ProfileDao, FoodsDao, RecognitionsDao, MealEntriesDao, KvDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  /// 测试专用：内存库 + 随用随弃，零真实 API、零文件副作用。
  @visibleForTesting
  AppDatabase.forTesting(File? file)
    : super(file == null ? NativeDatabase.memory() : NativeDatabase(file));

  // CLAUDE.md 未规定迁移策略；Task 1 首发，版本从 1 起。
  // TODO(decision): 后续表结构变更时接入 drift schema migration。
  @override
  int get schemaVersion => 1;
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(dir.path, 'paishiji.sqlite'));
    // Android 低版本 sqlite 需 Flutter 插件加载原生库。
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    return NativeDatabase(file, logStatements: false);
  });
}
