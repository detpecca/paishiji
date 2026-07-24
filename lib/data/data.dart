import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

import 'db/daos/foods_dao.dart';
import 'db/daos/kv_dao.dart';
import 'db/daos/meal_entries_dao.dart';
import 'db/daos/profile_dao.dart';
import 'db/daos/recognitions_dao.dart';
import 'db/database.dart';
import 'providers/seed_food_parser.dart';

// 拍食记数据层对外门面：AppDatabase + 各 DAO + 种子导入。
// 业务层（features/）只 import 本文件，不直接碰 Drift 生成代码。
export 'db/daos/foods_dao.dart';
export 'db/daos/kv_dao.dart';
export 'db/daos/meal_entries_dao.dart';
export 'db/daos/profile_dao.dart';
export 'db/daos/recognitions_dao.dart';
export 'db/database.dart';
export 'db/tables.dart';

/// 种子导入标志位（kv 中的 key）。值为导入时的 seed 版本号。
const kSeedVersionKey = 'seed_version';

/// 当前种子库版本。CLAUDE.md §5.5：升级时按 name 做差量合并，不覆盖用户修改。
const kCurrentSeedVersion = 1;

/// 数据层容器：持有 AppDatabase 与各 DAO，便于 Riverpod 注入与测试替换。
class DataScope {
  DataScope(this.db)
    : profileDao = db.profileDao,
      foodsDao = db.foodsDao,
      recognitionsDao = db.recognitionsDao,
      mealEntriesDao = db.mealEntriesDao,
      kvDao = db.kvDao;

  final AppDatabase db;
  final ProfileDao profileDao;
  final FoodsDao foodsDao;
  final RecognitionsDao recognitionsDao;
  final MealEntriesDao mealEntriesDao;
  final KvDao kvDao;

  /// 从 assets/seed_foods.json 加载原始 JSON 串。测试可注入 [bundler] 覆盖。
  static Future<String> loadSeedJson({AssetBundle? bundler}) async {
    final bundle = bundler ?? rootBundle;
    return bundle.loadString('assets/seed_foods.json');
  }

  /// 首次启动导入；重复启动按 kv 标志跳过。
  /// [now] 仅测试注入；生产由数据库 currentDateAndTime 自动填。
  static Future<void> ensureSeeded(
    DataScope scope, {
    String? seedJson,
    DateTime? now,
  }) async {
    final done = await scope.kvDao.get(kSeedVersionKey);
    if (done != null && int.parse(done) >= kCurrentSeedVersion) {
      return;
    }
    final json = seedJson ?? await loadSeedJson();
    final entries = SeedFoodParser.parse(json);
    await scope.foodsDao.upsertSeed(entries);
    await scope.kvDao.set(kSeedVersionKey, '$kCurrentSeedVersion');
  }

  /// 关闭数据库。Riverpod dispose 时调用。
  @visibleForTesting
  Future<void> close() => db.close();
}
