import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

// 餐次记录 DAO。
part 'meal_entries_dao.g.dart';

@DriftAccessor(tables: [MealEntries])
class MealEntriesDao extends DatabaseAccessor<AppDatabase>
    with _$MealEntriesDaoMixin {
  MealEntriesDao(super.db);

  Future<int> add(MealEntriesCompanion entry) =>
      into(mealEntries).insert(entry);

  /// 备份恢复：全量读取 + 指定 id 插入 + 清空。
  Future<List<MealEntry>> all() => select(mealEntries).get();
  Future<void> restore(MealEntriesCompanion entry) =>
      into(mealEntries).insert(entry, mode: InsertMode.insertOrReplace);
  Future<int> deleteAll() => mealEntries.delete().go();

  Future<List<MealEntry>> ofDate(String loggedDate) => (select(
    mealEntries,
  )..where((t) => t.loggedDate.equals(loggedDate))).get();

  Future<List<MealEntry>> ofDateAndMeal(String loggedDate, int mealType) =>
      (select(mealEntries)..where(
            (t) =>
                t.loggedDate.equals(loggedDate) & t.mealType.equals(mealType),
          ))
          .get();

  Future<int> remove(int id) =>
      (mealEntries.delete()..where((t) => t.id.equals(id))).go();

  /// 当日营养汇总（热量与三大营养素）。UI 上所有数字带"估算"角标（红线#1）。
  Future<({double calories, double protein, double carbs, double fat})>
  dailyTotals(String loggedDate) async {
    final rows = await ofDate(loggedDate);
    double cal = 0, pro = 0, carb = 0, fat = 0;
    for (final r in rows) {
      cal += r.calories;
      pro += r.proteinG;
      carb += r.carbsG;
      fat += r.fatG;
    }
    return (calories: cal, protein: pro, carbs: carb, fat: fat);
  }
}
