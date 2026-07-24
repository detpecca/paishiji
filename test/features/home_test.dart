// 拍食记 Task 6 单测：首页汇总=明细求和(误差<1kcal)、refresh 即时刷新、跨天滚动。
import 'package:drift/drift.dart' show driftRuntimeOptions, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/core/date_key.dart';
import 'package:paishiji/data/data.dart';
import 'package:paishiji/features/home/home_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DataScope scope;
  late HomeView view;

  setUp(() async {
    db = AppDatabase.forTesting(null);
    scope = DataScope(db);
    // 建档
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
    view = scope.homeView;
  });

  tearDown(() => db.close());

  Future<int> addFood({required String name}) async {
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

  group('HomeView 汇总 = 明细求和（误差 <1kcal）', () {
    test('多条记录：明细求和 == DAO 汇总 == view.consumedCalories', () async {
      final f1 = await addFood(name: '米饭');
      final f2 = await addFood(name: '鸡胸肉');
      final today = DateKey.today();
      await scope.mealEntriesDao.add(
        MealEntriesCompanion.insert(
          foodId: f1,
          grams: 200,
          mealType: 2,
          loggedDate: today,
          calories: 232,
          proteinG: 5.2,
          carbsG: 51.8,
          fatG: 0.6,
        ),
      );
      await scope.mealEntriesDao.add(
        MealEntriesCompanion.insert(
          foodId: f2,
          grams: 150,
          mealType: 2,
          loggedDate: today,
          calories: 199.5,
          proteinG: 46.5,
          carbsG: 0,
          fatG: 1.8,
        ),
      );

      await view.refresh();

      final entriesSum = view.entriesSumCalories;
      final viewSum = view.consumedCalories;
      final daoSum = await view.daoTotalCalories();

      expect((entriesSum - viewSum).abs(), lessThan(1));
      expect((daoSum - viewSum).abs(), lessThan(1));
      expect(viewSum, closeTo(431.5, 0.5));
    });

    test('空天：汇总 0、明细 0、误差 0', () async {
      await view.refresh();
      expect(view.consumedCalories, 0);
      expect(view.entriesSumCalories, 0);
    });
  });

  group('记录后即时刷新', () {
    test('add 后 refresh → view 反映新增', () async {
      await view.refresh();
      expect(view.consumedCalories, 0);
      expect(view.todayGroups, isEmpty);

      final f1 = await addFood(name: '米饭');
      await scope.mealEntriesDao.add(
        MealEntriesCompanion.insert(
          foodId: f1,
          grams: 200,
          mealType: 2,
          loggedDate: DateKey.today(),
          calories: 232,
          proteinG: 5.2,
          carbsG: 51.8,
          fatG: 0.6,
        ),
      );
      await view.refresh();

      expect(view.consumedCalories, closeTo(232, 0.5));
      expect(view.todayGroups, hasLength(1));
      expect(view.todayGroups.single.mealType, 2);
    });

    test('refresh 通知监听器', () async {
      var changed = 0;
      view.addListener(() => changed++);
      await view.refresh();
      expect(changed, greaterThan(0));
    });
  });

  group('0 点跨天正确滚动', () {
    test('23:59 与次日 00:01 取不同 key', () {
      final night = DateTime(2026, 7, 24, 23, 59);
      final morning = DateTime(2026, 7, 25, 0, 1);
      expect(DateKey.of(night), '2026-07-24');
      expect(DateKey.of(morning), '2026-07-25');
      expect(DateKey.of(night), isNot(DateKey.of(morning)));
    });

    test('refresh(now) 按注入时间取当日明细，跨天后看不到昨天记录', () async {
      final f1 = await addFood(name: '米饭');
      // 昨天 23:30 记录
      final yesterday = DateTime(2026, 7, 23, 23, 30);
      await scope.mealEntriesDao.add(
        MealEntriesCompanion.insert(
          foodId: f1,
          grams: 200,
          mealType: 3,
          loggedDate: DateKey.of(yesterday),
          calories: 232,
          proteinG: 5.2,
          carbsG: 51.8,
          fatG: 0.6,
        ),
      );

      // 当天 00:01 刷新：不应看到昨天晚餐
      await view.refresh(now: DateTime(2026, 7, 24, 0, 1));
      expect(view.todayGroups, isEmpty);
      expect(view.consumedCalories, 0);
    });

    test('DateKey.parse 回到当日 00:00', () {
      final d = DateKey.parse('2026-07-24');
      expect(d.year, 2026);
      expect(d.month, 7);
      expect(d.day, 24);
      expect(d.hour, 0);
    });
  });

  group('餐次分组顺序', () {
    test('早午晚加餐按固定顺序，空餐次不出现', () async {
      final f1 = await addFood(name: '米饭');
      await scope.mealEntriesDao.add(
        MealEntriesCompanion.insert(
          foodId: f1,
          grams: 100,
          mealType: 1,
          loggedDate: DateKey.today(),
          calories: 50,
          proteinG: 1,
          carbsG: 10,
          fatG: 0.3,
        ),
      );
      await scope.mealEntriesDao.add(
        MealEntriesCompanion.insert(
          foodId: f1,
          grams: 100,
          mealType: 3,
          loggedDate: DateKey.today(),
          calories: 50,
          proteinG: 1,
          carbsG: 10,
          fatG: 0.3,
        ),
      );
      await view.refresh();
      final groups = view.todayGroups;
      expect(groups.map((g) => g.mealType), [1, 3]);
    });
  });
}
