// 拍食记 RecognitionController 单测。滑块联动重算 + swapTo + save 写库。
// 红线#2：零真实 API。
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/data/data.dart';
import 'package:paishiji/data/providers/image_processor.dart';
import 'package:paishiji/data/providers/recognition_pipeline.dart';
import 'package:paishiji/data/providers/vision_provider.dart';
import 'package:paishiji/domain/nutrition_matcher.dart';
import 'package:paishiji/domain/traffic_light_engine.dart';
import 'package:paishiji/features/recognition/recognition_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DataScope scope;

  setUp(() async {
    db = AppDatabase.forTesting(null);
    scope = DataScope(db);
    const seed = '''
      [{"name":"番茄炒蛋","aliases":["西红柿炒蛋"],"calories_per_100g":86,"protein_per_100g":5.6,"carbs_per_100g":4.4,"fat_per_100g":5.1,"source":1},
       {"name":"米饭","aliases":[],"calories_per_100g":116,"protein_per_100g":2.6,"carbs_per_100g":25.9,"fat_per_100g":0.3,"source":1}]
    ''';
    await DataScope.ensureSeeded(scope, seedJson: seed);
  });

  tearDown(() => db.close());

  const daily = DailyContext(
    goalType: 1,
    targetCalories: 1751,
    consumedCalories: 0,
    targetProtein: 140,
    consumedProtein: 0,
  );

  /// 跑一次 pipeline 拿到默认 2 项结果，构造 EditableItem。
  Future<List<EditableItem>> buildItems() async {
    final pipeline = RecognitionPipeline(
      imageProcessor: const MockImageProcessor(),
      vision: const MockVisionProvider(),
      scope: scope,
      daily: daily,
    );
    final result = await pipeline.run('/tmp/x.jpg');
    final items = <EditableItem>[];
    for (final v in result.items) {
      final f = await scope.foodsDao.findById(v.foodId!);
      final fr = FoodRecord(
        id: f!.id,
        name: f.name,
        aliasesJson: f.aliases,
        caloriesPer100g: f.caloriesPer100g,
        proteinPer100g: f.proteinPer100g,
        carbsPer100g: f.carbsPer100g,
        fatPer100g: f.fatPer100g,
      );
      items.add(
        EditableItem(view: v, per100g: fr, daily: daily, sugarPer100g: 0),
      );
    }
    return items;
  }

  group('EditableItem 滑块联动重算', () {
    test('grams 改 → 营养按比例变（无 async，纯本地重算，无闪烁）', () {
      // 构造一个不依赖库的 EditableItem
      const fr = FoodRecord(
        id: 1,
        name: '番茄炒蛋',
        aliasesJson: '[]',
        caloriesPer100g: 86,
        proteinPer100g: 5.6,
        carbsPer100g: 4.4,
        fatPer100g: 5.1,
      );
      const view = RecognizedItemView(
        detectedName: '番茄炒蛋',
        confidence: 0.9,
        estGrams: 250,
        calories: 0,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        signal: Signal.green,
        advice: '',
      );
      final item = EditableItem(
        view: view,
        per100g: fr,
        daily: daily,
        sugarPer100g: 0,
      );

      // 初始 250g：86*2.5=215
      expect(item.calories, closeTo(215, 0.5));
      expect(item.protein, closeTo(14, 0.5));

      // 滑到 200g：86*2=172
      item.setGrams(200);
      expect(item.grams, 200);
      expect(item.calories, closeTo(172, 0.5));
      expect(item.protein, closeTo(11.2, 0.5));

      // 滑到非 50 倍数 → 自动 50 步进
      item.setGrams(175);
      expect(item.grams, 150); // 175 ~/ 50 = 3 → 150
    });

    test('滑到 <50 → 兜底 50', () {
      const fr = FoodRecord(
        id: 1,
        name: 'x',
        aliasesJson: '[]',
        caloriesPer100g: 100,
        proteinPer100g: 10,
        carbsPer100g: 0,
        fatPer100g: 0,
      );
      const view = RecognizedItemView(
        detectedName: 'x',
        confidence: 0.9,
        estGrams: 100,
        calories: 0,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        signal: Signal.green,
        advice: '',
      );
      final item = EditableItem(
        view: view,
        per100g: fr,
        daily: daily,
        sugarPer100g: 0,
      );
      item.setGrams(10);
      expect(item.grams, 50);
    });

    test('trafficLight 随 grams 实时重算（250g 绿→800g 可能转红超预算）', () {
      const fr = FoodRecord(
        id: 1,
        name: '番茄炒蛋',
        aliasesJson: '[]',
        caloriesPer100g: 86,
        proteinPer100g: 5.6,
        carbsPer100g: 4.4,
        fatPer100g: 5.1,
      );
      const view = RecognizedItemView(
        detectedName: '番茄炒蛋',
        confidence: 0.9,
        estGrams: 250,
        calories: 0,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        signal: Signal.green,
        advice: '',
      );
      final item = EditableItem(
        view: view,
        per100g: fr,
        daily: daily,
        sugarPer100g: 0,
      );
      expect(item.trafficLight.signal, Signal.green); // 215/1751≈12%

      item.setGrams(800); // 688kcal / 1751 ≈ 39% > 30%
      expect(item.trafficLight.signal, Signal.yellow);
    });

    test('swapTo 换食物，保留 grams', () {
      const fr1 = FoodRecord(
        id: 1,
        name: '番茄炒蛋',
        aliasesJson: '[]',
        caloriesPer100g: 86,
        proteinPer100g: 5.6,
        carbsPer100g: 4.4,
        fatPer100g: 5.1,
      );
      const fr2 = FoodRecord(
        id: 2,
        name: '米饭',
        aliasesJson: '[]',
        caloriesPer100g: 116,
        proteinPer100g: 2.6,
        carbsPer100g: 25.9,
        fatPer100g: 0.3,
      );
      const view = RecognizedItemView(
        detectedName: '番茄炒蛋',
        confidence: 0.9,
        estGrams: 250,
        calories: 0,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        signal: Signal.green,
        advice: '',
      );
      final item = EditableItem(
        view: view,
        per100g: fr1,
        daily: daily,
        sugarPer100g: 0,
      );
      expect(item.calories, closeTo(215, 0.5));
      item.swapTo(fr2); // 换成米饭，grams 不变 250
      expect(item.grams, 250);
      expect(item.calories, closeTo(290, 0.5)); // 116*2.5
    });
  });

  group('RecognitionDraft 合计联动', () {
    test('totalCalories 随某项 grams 变', () {
      const fr = FoodRecord(
        id: 1,
        name: 'x',
        aliasesJson: '[]',
        caloriesPer100g: 100,
        proteinPer100g: 10,
        carbsPer100g: 0,
        fatPer100g: 0,
      );
      const view = RecognizedItemView(
        detectedName: 'x',
        confidence: 0.9,
        estGrams: 100,
        calories: 0,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        signal: Signal.green,
        advice: '',
      );
      final a = EditableItem(
        view: view,
        per100g: fr,
        daily: daily,
        sugarPer100g: 0,
      );
      final b = EditableItem(
        view: view,
        per100g: fr,
        daily: daily,
        sugarPer100g: 0,
      );
      final draft = RecognitionDraft(items: [a, b]);
      expect(draft.totalCalories, closeTo(200, 0.5)); // 2×100g×100
      a.setGrams(200); // a 变 200g → 200kcal
      expect(draft.totalCalories, closeTo(300, 0.5));
    });

    test('setMealType 通知', () {
      final draft = RecognitionDraft(items: []);
      var changed = 0;
      draft.addListener(() => changed++);
      draft.setMealType(3);
      expect(changed, greaterThan(0));
      expect(draft.mealType, 3);
    });
  });

  group('RecognitionController.archiveToday 写库', () {
    test('存入今日写 meal_entries（命中项写库，未命中跳过）', () async {
      final items = await buildItems();
      final draft = RecognitionDraft(items: items, mealType: 2);
      final ctrl = RecognitionController(scope: scope, draft: draft);
      final r = await ctrl.archiveToday('2026-07-24');
      expect(r.writtenIds, hasLength(2)); // 番茄炒蛋 + 米饭 都命中
      final entries = await scope.mealEntriesDao.ofDate('2026-07-24');
      expect(entries, hasLength(2));
      expect(entries.every((e) => e.mealType == 2), isTrue);
      // 汇总应等于 draft 合计
      final totals = await scope.mealEntriesDao.dailyTotals('2026-07-24');
      expect(totals.calories, closeTo(draft.totalCalories, 1));
    });

    test('未命中项（foodId=null）跳过不写', () async {
      const fr = FoodRecord(
        id: -1,
        name: '未知菜',
        aliasesJson: '[]',
        caloriesPer100g: 0,
        proteinPer100g: 0,
        carbsPer100g: 0,
        fatPer100g: 0,
      );
      const view = RecognizedItemView(
        detectedName: '未知菜',
        confidence: 0.6,
        estGrams: 200,
        calories: 0,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        signal: Signal.green,
        advice: '',
        foodId: null,
      );
      final item = EditableItem(
        view: view,
        per100g: fr,
        daily: daily,
        sugarPer100g: 0,
      );
      final draft = RecognitionDraft(items: [item]);
      final ctrl = RecognitionController(scope: scope, draft: draft);
      final r = await ctrl.archiveToday('2026-07-24');
      expect(r.writtenIds, isEmpty);
    });
  });

  group('低置信度判定', () {
    test('confidence < 0.7 → lowConfidence', () {
      const fr = FoodRecord(
        id: 1,
        name: 'x',
        aliasesJson: '[]',
        caloriesPer100g: 100,
        proteinPer100g: 1,
        carbsPer100g: 1,
        fatPer100g: 1,
      );
      const view = RecognizedItemView(
        detectedName: 'x',
        confidence: 0.65,
        estGrams: 100,
        calories: 0,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        signal: Signal.green,
        advice: '',
      );
      expect(
        EditableItem(
          view: view,
          per100g: fr,
          daily: daily,
          sugarPer100g: 0,
        ).lowConfidence,
        isTrue,
      );
    });
    test('confidence ≥ 0.7 → 非 lowConfidence', () {
      const fr = FoodRecord(
        id: 1,
        name: 'x',
        aliasesJson: '[]',
        caloriesPer100g: 100,
        proteinPer100g: 1,
        carbsPer100g: 1,
        fatPer100g: 1,
      );
      const view = RecognizedItemView(
        detectedName: 'x',
        confidence: 0.7,
        estGrams: 100,
        calories: 0,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        signal: Signal.green,
        advice: '',
      );
      expect(
        EditableItem(
          view: view,
          per100g: fr,
          daily: daily,
          sugarPer100g: 0,
        ).lowConfidence,
        isFalse,
      );
    });
  });
}
