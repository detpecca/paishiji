// 拍食记 DAO + seed 导入单测。内存库，零真实 API、零文件副作用。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/data/data.dart';

void main() {
  late AppDatabase db;
  late DataScope scope;

  setUp(() {
    db = AppDatabase.forTesting(null);
    scope = DataScope(db);
  });

  tearDown(() => db.close());

  group('FoodsDao CRUD', () {
    test('新增并按 id/名/条码查询', () async {
      final id = await scope.foodsDao.addOne(
        FoodsCompanion.insert(
          name: '鸡胸肉',
          aliases: const Value('["鸡胸"]'),
          caloriesPer100g: 133.0,
          proteinPer100g: 31.0,
          carbsPer100g: 0.0,
          fatPer100g: 1.2,
          source: 1,
          barcode: const Value('5000'),
        ),
      );
      expect(id, greaterThan(0));
      expect((await scope.foodsDao.findById(id))?.name, '鸡胸肉');
      expect((await scope.foodsDao.findByName('鸡胸肉'))?.id, id);
      expect((await scope.foodsDao.findByBarcode('5000'))?.id, id);
    });

    test('按名/别名模糊搜索', () async {
      await scope.foodsDao.addOne(
        FoodsCompanion.insert(
          name: '番茄炒蛋',
          aliases: const Value('["西红柿炒蛋"]'),
          caloriesPer100g: 86.0,
          proteinPer100g: 5.6,
          carbsPer100g: 4.4,
          fatPer100g: 5.1,
          source: 1,
        ),
      );
      final byName = await scope.foodsDao.searchByNameOrAlias('番茄');
      expect(byName, hasLength(1));
      final byAlias = await scope.foodsDao.searchByNameOrAlias('西红柿');
      expect(byAlias, hasLength(1));
    });

    test('待确认列表只返回 source=2 且 verified=0', () async {
      await scope.foodsDao.addOne(
        FoodsCompanion.insert(
          name: 'AI估食物',
          aliases: const Value('[]'),
          caloriesPer100g: 50.0,
          proteinPer100g: 5.0,
          carbsPer100g: 5.0,
          fatPer100g: 1.0,
          source: 2,
        ),
      );
      await scope.foodsDao.addOne(
        FoodsCompanion.insert(
          name: '种子食物',
          aliases: const Value('[]'),
          caloriesPer100g: 30.0,
          proteinPer100g: 3.0,
          carbsPer100g: 3.0,
          fatPer100g: 0.5,
          source: 1,
        ),
      );
      final pending = await scope.foodsDao.pendingVerification();
      expect(pending, hasLength(1));
      expect(pending.single.name, 'AI估食物');
    });

    test('markVerified 置 1', () async {
      final id = await scope.foodsDao.addOne(
        FoodsCompanion.insert(
          name: '待确认',
          aliases: const Value('[]'),
          caloriesPer100g: 50.0,
          proteinPer100g: 5.0,
          carbsPer100g: 5.0,
          fatPer100g: 1.0,
          source: 2,
        ),
      );
      await scope.foodsDao.markVerified(id);
      expect((await scope.foodsDao.findById(id))?.verified, 1);
      expect(await scope.foodsDao.pendingVerification(), isEmpty);
    });

    test('upsertSeed 按 name 唯一，重复插入不翻倍', () async {
      final entries = [
        FoodsCompanion.insert(
          name: '米饭',
          aliases: const Value('[]'),
          caloriesPer100g: 116.0,
          proteinPer100g: 2.6,
          carbsPer100g: 25.9,
          fatPer100g: 0.3,
          source: 1,
        ),
      ];
      await scope.foodsDao.upsertSeed(entries);
      await scope.foodsDao.upsertSeed(entries); // 重复
      expect(await scope.foodsDao.all(), hasLength(1));
    });
  });

  group('ProfileDao', () {
    test('未建档返回 null，upsert 后可读回，updateTargets 不丢字段', () async {
      expect(await scope.profileDao.get(), isNull);
      final now = DateTime.utc(2026, 7, 24);
      await scope.profileDao.upsert(
        ProfilesCompanion.insert(
          gender: 1,
          birthYear: 2001,
          heightCm: 175.0,
          weightKg: 70.0,
          activityLevel: 2,
          goalType: 1,
          goalRate: 2,
          targetCalories: 1700,
          proteinG: 140.0,
          carbsG: 170.0,
          fatG: 47.0,
          updatedAt: now,
        ),
      );
      final p = await scope.profileDao.get();
      expect(p?.gender, 1);
      expect(p?.targetCalories, 1700);
      await scope.profileDao.updateTargets(
        targetCalories: 1800,
        proteinG: 150.0,
        carbsG: 180.0,
        fatG: 50.0,
        updatedAt: now,
      );
      final p2 = await scope.profileDao.get();
      expect(p2?.targetCalories, 1800);
      expect(p2?.proteinG, 150.0);
      expect(p2?.heightCm, 175.0); // 未被覆盖
    });
  });

  group('MealEntriesDao', () {
    test('新增、按日/餐次查询、删除、当日汇总', () async {
      final foodId = await scope.foodsDao.addOne(
        FoodsCompanion.insert(
          name: '米饭',
          aliases: const Value('[]'),
          caloriesPer100g: 116.0,
          proteinPer100g: 2.6,
          carbsPer100g: 25.9,
          fatPer100g: 0.3,
          source: 1,
        ),
      );
      final id = await scope.mealEntriesDao.add(
        MealEntriesCompanion.insert(
          foodId: foodId,
          grams: 200,
          mealType: 2,
          loggedDate: '2026-07-24',
          calories: 232.0,
          proteinG: 5.2,
          carbsG: 51.8,
          fatG: 0.6,
        ),
      );
      expect(await scope.mealEntriesDao.ofDate('2026-07-24'), hasLength(1));
      expect(
        await scope.mealEntriesDao.ofDateAndMeal('2026-07-24', 2),
        hasLength(1),
      );
      expect(
        await scope.mealEntriesDao.ofDateAndMeal('2026-07-24', 1),
        isEmpty,
      );
      final totals = await scope.mealEntriesDao.dailyTotals('2026-07-24');
      expect(totals.calories, 232.0);
      expect(totals.protein, 5.2);
      expect(await scope.mealEntriesDao.remove(id), 1);
      expect(await scope.mealEntriesDao.ofDate('2026-07-24'), isEmpty);
    });
  });

  group('RecognitionsDao', () {
    test('一次识别写 recognitions + items，可按 recognitionId 回读，可纠正', () async {
      final rid = await scope.recognitionsDao.createRecognition(
        imagePath: '/tmp/a.jpg',
        provider: 'qwen',
        latencyMs: 1200,
        rawJson: '[]',
      );
      await scope.recognitionsDao.addItems([
        RecognitionItemsCompanion.insert(
          recognitionId: rid,
          detectedName: '番茄炒蛋',
          confidence: 0.9,
          estGrams: 250,
          calories: 215.0,
          proteinG: 14.0,
          carbsG: 11.0,
          fatG: 12.75,
          signal: 0,
        ),
      ]);
      final items = await scope.recognitionsDao.itemsOf(rid);
      expect(items, hasLength(1));
      expect(items.single.detectedName, '番茄炒蛋');
      await scope.recognitionsDao.applyCorrection(
        itemId: items.single.id,
        foodId: 5,
        grams: 200,
      );
      final fixed = (await scope.recognitionsDao.itemsOf(rid)).single;
      expect(fixed.correctedFoodId, 5);
      expect(fixed.correctedGrams, 200);
    });
  });

  group('KvDao', () {
    test('get/set/remove', () async {
      expect(await scope.kvDao.get('k'), isNull);
      await scope.kvDao.set('k', 'v1');
      expect(await scope.kvDao.get('k'), 'v1');
      await scope.kvDao.set('k', 'v2'); // 覆盖
      expect(await scope.kvDao.get('k'), 'v2');
      await scope.kvDao.set('k', null); // 允许 null 值
      expect(await scope.kvDao.get('k'), isNull);
      expect(await scope.kvDao.remove('k'), 1);
      expect(await scope.kvDao.get('k'), isNull);
    });
  });

  group('DataScope.ensureSeeded', () {
    test('冷启动导入 50 条', () async {
      final json =
          '[${List.generate(50, (i) => '{"name":"种子_$i","calories_per_100g":${10 + i}.0,"protein_per_100g":1.0,"carbs_per_100g":2.0,"fat_per_100g":0.5,"source":1}').join(',')}]';
      await DataScope.ensureSeeded(scope, seedJson: json);
      expect(await scope.foodsDao.all(), hasLength(50));
      expect(await scope.kvDao.get(kSeedVersionKey), '1');
    });

    test('重复启动不重复导入（kv 标志命中即返回）', () async {
      const json =
          '[{"name":"仅一条","calories_per_100g":10.0,"protein_per_100g":1.0,"carbs_per_100g":1.0,"fat_per_100g":1.0,"source":1}]';
      await DataScope.ensureSeeded(scope, seedJson: json);
      final countAfterFirst = (await scope.foodsDao.all()).length;
      // 再次调用，传入不同 JSON 也应被跳过
      const json2 =
          '[{"name":"新条","calories_per_100g":20.0,"protein_per_100g":2.0,"carbs_per_100g":2.0,"fat_per_100g":2.0,"source":1}]';
      await DataScope.ensureSeeded(scope, seedJson: json2);
      final countAfterSecond = (await scope.foodsDao.all()).length;
      expect(countAfterSecond, countAfterFirst);
    });
  });
}
