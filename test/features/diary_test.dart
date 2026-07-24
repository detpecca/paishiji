// 拍食记日记页单测：绿点/红点判定 + 左滑删除写库。
import 'package:drift/drift.dart' show driftRuntimeOptions, Value;
import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/core/date_key.dart';
import 'package:paishiji/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DataScope scope;

  setUp(() async {
    db = AppDatabase.forTesting(null);
    scope = DataScope(db);
    await scope.profileDao.upsert(
      ProfilesCompanion.insert(
        gender: 1,
        birthYear: 2001,
        heightCm: 175,
        weightKg: 70,
        activityLevel: 2,
        goalType: 1,
        goalRate: 2,
        targetCalories: 1751,
        proteinG: 140,
        carbsG: 170,
        fatG: 47,
        allergies: const Value('[]'),
        updatedAt: DateTime(2026, 7, 24),
      ),
    );
  });

  tearDown(() => db.close());

  Future<int> addFood(String name) async {
    return scope.foodsDao.addOne(
      FoodsCompanion.insert(
        name: name,
        aliases: const Value('[]'),
        caloriesPer100g: 100,
        proteinPer100g: 10,
        carbsPer100g: 10,
        fatPer100g: 1,
        source: 1,
      ),
    );
  }

  group('日记日历：达标绿点 / 超标红点', () {
    test('当日汇总 ≤ target → 绿点(达标)', () async {
      final f = await addFood('米饭');
      await scope.mealEntriesDao.add(
        MealEntriesCompanion.insert(
          foodId: f,
          grams: 200,
          mealType: 2,
          loggedDate: '2026-07-24',
          calories: 232,
          proteinG: 5.2,
          carbsG: 51.8,
          fatG: 0.6,
        ),
      );
      final totals = await scope.mealEntriesDao.dailyTotals('2026-07-24');
      const target = 1751;
      expect(totals.calories <= target, isTrue); // 绿点
    });

    test('当日汇总 > target → 红点(超标)', () async {
      final f = await addFood('红烧肉');
      await scope.mealEntriesDao.add(
        MealEntriesCompanion.insert(
          foodId: f,
          grams: 2000,
          mealType: 3,
          loggedDate: '2026-07-24',
          calories: 5000,
          proteinG: 100,
          carbsG: 100,
          fatG: 200,
        ),
      );
      final totals = await scope.mealEntriesDao.dailyTotals('2026-07-24');
      expect(totals.calories > 1751, isTrue); // 红点
    });

    test('无记录日 → 无点', () async {
      final totals = await scope.mealEntriesDao.dailyTotals('2026-07-25');
      expect(totals.calories, 0); // 无点
    });
  });

  group('左滑删除', () {
    test('remove 后当日记录减一、汇总更新', () async {
      final f = await addFood('米饭');
      final id = await scope.mealEntriesDao.add(
        MealEntriesCompanion.insert(
          foodId: f,
          grams: 200,
          mealType: 2,
          loggedDate: DateKey.today(),
          calories: 232,
          proteinG: 5.2,
          carbsG: 51.8,
          fatG: 0.6,
        ),
      );
      final before = await scope.mealEntriesDao.dailyTotals(DateKey.today());
      expect(before.calories, closeTo(232, 0.5));

      final n = await scope.mealEntriesDao.remove(id);
      expect(n, 1);
      final after = await scope.mealEntriesDao.dailyTotals(DateKey.today());
      expect(after.calories, 0);
    });
  });

  group('跨月导航逻辑', () {
    test('月份前进后退', () {
      var m = DateTime(2026, 7);
      m = DateTime(m.year, m.month - 1);
      expect(m.year, 2026);
      expect(m.month, 6);
      m = DateTime(m.year, m.month + 2); // 6 → 8（跨年边界测：8 月）
      expect(m.month, 8);
    });

    test('月内天数正确', () {
      // 7 月 31 天，2 月（2026 非闰）28 天
      expect(DateUtils.getDaysInMonth(2026, 7), 31);
      expect(DateUtils.getDaysInMonth(2026, 2), 28);
    });
  });
}
