// 拍食记 Task 8 单测：BackupService 导出→导入完整还原（含 schema 校验/拒绝错版本）、
// StatsService 月度计数、备份提醒 7 天阈值、R3 文案修复。
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/data/data.dart';
import 'package:paishiji/data/providers/backup_service.dart';
import 'package:paishiji/data/providers/stats_service.dart';
import 'package:paishiji/domain/traffic_light_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DataScope scope;

  setUp(() async {
    db = AppDatabase.forTesting(null);
    scope = DataScope(db);
  });

  tearDown(() => db.close());

  Future<void> seedProfile() async {
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
        updatedAt: DateTime(2026, 7, 26),
      ),
    );
  }

  Future<int> addFood(String name, {String? barcode}) async {
    return scope.foodsDao.addOne(
      FoodsCompanion.insert(
        name: name,
        aliases: const Value('[]'),
        caloriesPer100g: 100,
        proteinPer100g: 10,
        carbsPer100g: 10,
        fatPer100g: 1,
        source: 1,
        barcode: barcode == null ? const Value.absent() : Value(barcode),
      ),
    );
  }

  group('BackupService：导出 → 导入 完整还原', () {
    test('DoD：卸载重装后导入备份完整还原（profile+foods+meal_entries+kv）', () async {
      await seedProfile();
      final f1 = await addFood('米饭');
      await addFood('鸡胸肉', barcode: '1234567890');
      await scope.mealEntriesDao.add(
        MealEntriesCompanion.insert(
          foodId: f1,
          grams: 200,
          mealType: 2,
          loggedDate: '2026-07-26',
          calories: 232,
          proteinG: 5.2,
          carbsG: 51.8,
          fatG: 0.6,
        ),
      );
      await scope.kvDao.set('my_pref', 'dark');
      await scope.kvDao.set(kSeedVersionKey, '$kCurrentSeedVersion');

      // 导出（用真实临时目录）
      final exportedPath = await BackupService(scope).export();
      final raw = await File(exportedPath).readAsString();

      // 模拟"卸载重装"：新内存库 + 新 scope。
      await db.close();
      db = AppDatabase.forTesting(null);
      scope = DataScope(db);

      // 导入。
      await BackupService(scope).import(raw);

      // 验证完整还原。
      final profile = await scope.profileDao.get();
      expect(profile, isNotNull);
      expect(profile!.targetCalories, 1751);
      expect(profile.proteinG, 140);

      final foods = await scope.foodsDao.all();
      expect(foods, hasLength(2));
      final rice = foods.firstWhere((f) => f.name == '米饭');
      expect(rice.caloriesPer100g, 100);
      final chicken = foods.firstWhere((f) => f.name == '鸡胸肉');
      expect(chicken.barcode, '1234567890');

      final entries = await scope.mealEntriesDao.ofDate('2026-07-26');
      expect(entries, hasLength(1));
      expect(entries.single.calories, 232);

      expect(await scope.kvDao.get('my_pref'), 'dark');
      expect(await scope.kvDao.get(kSeedVersionKey), '$kCurrentSeedVersion');
    });

    test('导入写入 last_backup_at（首页据此判断提醒）', () async {
      await seedProfile();
      final svc = BackupService(scope);
      expect(await scope.kvDao.get('last_backup_at'), isNull);
      await svc.export();
      expect(await scope.kvDao.get('last_backup_at'), isNotNull);
    });

    test('schema 版本不匹配 → 拒绝导入', () async {
      final bad = jsonEncode({
        'schema_version': 999,
        'exported_at': '2026-07-26T00:00:00',
        'profile': null,
        'foods': const <Map<String, dynamic>>[],
        'recognitions': const <Map<String, dynamic>>[],
        'recognition_items': const <Map<String, dynamic>>[],
        'meal_entries': const <Map<String, dynamic>>[],
        'kv': const <Map<String, dynamic>>[],
      });
      expect(
        () => BackupService(scope).import(bad),
        throwsA(isA<BackupException>()),
      );
    });

    test('非法 JSON → 拒绝导入', () {
      expect(
        () => BackupService(scope).import('not json'),
        throwsA(isA<BackupException>()),
      );
    });
  });

  group('BackupPayload.tryParse', () {
    test('合法 JSON 解析', () {
      const raw =
          '{"schema_version":1,"exported_at":"x","foods":'
          '[{"name":"米饭","caloriesPer100g":116}]}';
      final p = BackupPayload.tryParse(raw);
      expect(p, isNotNull);
      expect(p!.schemaVersion, 1);
      expect(p.foods, hasLength(1));
    });

    test('缺 schema_version → null', () {
      const raw = '{"exported_at":"x"}';
      expect(BackupPayload.tryParse(raw), isNull);
    });
  });

  group('StatsService：本月识别计数', () {
    test('初始 0，increment 后 1，估算花费 = 次数×0.03', () async {
      final now = DateTime(2026, 7, 26, 12);
      final svc = StatsService(scope, now: () => now);
      var stats = await svc.currentMonth();
      expect(stats.count, 0);
      expect(stats.monthKey, '2026-07');
      expect(stats.estimatedCostRmb, 0);

      await svc.incrementRecognition();
      stats = await svc.currentMonth();
      expect(stats.count, 1);
      expect(stats.estimatedCostRmb, closeTo(0.03, 0.001));
    });

    test('跨月不计入上月', () async {
      // 7 月记 2 次。
      var svc = StatsService(scope, now: () => DateTime(2026, 7, 26));
      await svc.incrementRecognition();
      await svc.incrementRecognition();
      // 8 月读：应为 0（不同 kv key）。
      svc = StatsService(scope, now: () => DateTime(2026, 8, 1));
      final aug = await svc.currentMonth();
      expect(aug.count, 0);
      expect(aug.monthKey, '2026-08');
    });
  });

  group('首页备份提醒：7 天阈值', () {
    test('从未备份 → 需要提醒', () async {
      await seedProfile();
      final view = scope.homeView;
      await view.refresh(now: DateTime(2026, 7, 26, 12));
      expect(view.needsBackupReminder, isTrue);
    });

    test('刚刚备份 → 不提醒', () async {
      await seedProfile();
      await BackupService(scope, now: () => DateTime(2026, 7, 26, 12)).export();
      final view = scope.homeView;
      await view.refresh(now: DateTime(2026, 7, 26, 13));
      expect(view.needsBackupReminder, isFalse);
    });

    test('备份后第 8 天 → 再提醒', () async {
      await seedProfile();
      await BackupService(scope, now: () => DateTime(2026, 7, 1, 12)).export();
      final view = scope.homeView;
      await view.refresh(now: DateTime(2026, 7, 9, 12)); // 8 天后
      expect(view.needsBackupReminder, isTrue);
    });

    test('备份后第 6 天 → 不提醒', () async {
      await seedProfile();
      await BackupService(scope, now: () => DateTime(2026, 7, 1, 12)).export();
      final view = scope.homeView;
      await view.refresh(now: DateTime(2026, 7, 7, 12)); // 6 天后
      expect(view.needsBackupReminder, isFalse);
    });
  });

  group('R3 文案修复（Task 8 打磨）', () {
    const baseDaily = DailyContext(
      goalType: 1,
      targetCalories: 1751,
      consumedCalories: 0,
      targetProtein: 140,
      consumedProtein: 0,
    );

    test('只高糖 → "高糖，减脂期不建议"，不含"高脂"', () {
      const food = FoodNutrition(
        name: '蛋糕',
        grams: 100,
        caloriesPer100g: 350,
        proteinPer100g: 5,
        carbsPer100g: 50,
        fatPer100g: 10,
        sugarPer100g: 25,
      );
      final r = TrafficLightEngine.evaluate(food: food, daily: baseDaily);
      expect(r.signal, Signal.red);
      expect(r.advice, contains('高糖'));
      expect(r.advice, isNot(contains('高脂')));
    });

    test('高糖又高脂 → "高糖，高脂，减脂期不建议"', () {
      const food = FoodNutrition(
        name: '黄油蛋糕',
        grams: 100,
        caloriesPer100g: 500,
        proteinPer100g: 5,
        carbsPer100g: 50,
        fatPer100g: 25,
        sugarPer100g: 30,
      );
      final r = TrafficLightEngine.evaluate(food: food, daily: baseDaily);
      expect(r.advice, contains('高糖'));
      expect(r.advice, contains('高脂'));
    });
  });
}
