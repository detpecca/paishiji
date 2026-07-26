// 拍食记 Task 7 单测：OpenFoodFacts Mock 命中/未命中、NutritionLabel Mock 解析、
// 未命中 source=2 入库、条码二次命中、sugar 接线。
import 'package:drift/drift.dart' show driftRuntimeOptions, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/core/app_exceptions.dart';
import 'package:paishiji/data/data.dart';
import 'package:paishiji/data/providers/barcode_flow.dart';
import 'package:paishiji/data/providers/image_processor.dart';
import 'package:paishiji/data/providers/nutrition_estimate_provider.dart';
import 'package:paishiji/data/providers/nutrition_label_provider.dart';
import 'package:paishiji/data/providers/open_food_facts.dart';
import 'package:paishiji/data/providers/recognition_pipeline.dart';
import 'package:paishiji/data/providers/vision_provider.dart';
import 'package:paishiji/domain/nutrition_matcher.dart';
import 'package:paishiji/domain/traffic_light_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DataScope scope;

  const daily = DailyContext(
    goalType: 1,
    targetCalories: 1751,
    consumedCalories: 0,
    targetProtein: 140,
    consumedProtein: 0,
  );

  setUp(() async {
    db = AppDatabase.forTesting(null);
    scope = DataScope(db);
  });

  tearDown(() => db.close());

  group('OpenFoodFactsClient（Mock）', () {
    test('扫可乐命中', () async {
      const c = MockOpenFoodFactsClient();
      final r = await c.lookup('5449000000997');
      expect(r, isNotNull);
      expect(r!.name, '可口可乐');
      expect(r.caloriesPer100g, 42);
      expect(r.sugarPer100g, 10.6);
      expect(r.barcode, '5449000000997');
    });

    test('未知条码 → null', () async {
      const c = MockOpenFoodFactsClient();
      final r = await c.lookup('0000000000000');
      expect(r, isNull);
    });

    test('net-error → NetworkException', () async {
      const c = MockOpenFoodFactsClient();
      expect(() => c.lookup('net-error'), throwsA(isA<NetworkException>()));
    });
  });

  group('BarcodeFlow：扫码 → 命中 → 二次扫码直接命中', () {
    test('DoD：扫可乐命中 + 入库 source=3', () async {
      final flow = BarcodeFlow(
        openFoodFacts: const MockOpenFoodFactsClient(),
        labelProvider: const MockLabelProvider(),
        imageProcessor: const MockImageProcessor(),
        scope: scope,
      );
      final r = await flow.lookup('5449000000997');
      expect(r, isNotNull);
      expect(r!.foodRecord.name, '可口可乐');
      expect(r.fromCache, isFalse);

      // 入库 source=3
      final food = await scope.foodsDao.findByBarcode('5449000000997');
      expect(food, isNotNull);
      expect(food!.source, 3);
      expect(food.verified, 0);
      expect(food.sugarPer100g, 10.6);
    });

    test('DoD：补录商品二次扫码直接命中本地库', () async {
      final flow = BarcodeFlow(
        openFoodFacts: const MockOpenFoodFactsClient(),
        labelProvider: const MockLabelProvider(),
        imageProcessor: const MockImageProcessor(),
        scope: scope,
      );
      // 第一次扫码命中 Open Food Facts，入库。
      final r1 = await flow.lookup('5449000000997');
      expect(r1, isNotNull);
      expect(r1!.fromCache, isFalse);

      // 第二次扫码同一条码 → 直接命中本地库（fromCache=true）。
      final r2 = await flow.lookup('5449000000997');
      expect(r2, isNotNull);
      expect(r2!.fromCache, isTrue);
      expect(r2.foodRecord.barcode, '5449000000997');
    });

    test('未知条码 → null（引导补录）', () async {
      final flow = BarcodeFlow(
        openFoodFacts: const MockOpenFoodFactsClient(),
        labelProvider: const MockLabelProvider(),
        imageProcessor: const MockImageProcessor(),
        scope: scope,
      );
      final r = await flow.lookup('0000000000000');
      expect(r, isNull);
    });

    test('拍营养表补录 → 入库 source=3 + 二次扫码命中', () async {
      final flow = BarcodeFlow(
        openFoodFacts: const MockOpenFoodFactsClient(),
        labelProvider: const MockLabelProvider(),
        imageProcessor: const MockImageProcessor(),
        scope: scope,
      );
      // 未知条码 → null。
      expect(await flow.lookup('9999999999999'), isNull);
      // 拍营养表补录。
      final r = await flow.supplementFromLabel(
        barcode: '9999999999999',
        imagePath: '/tmp/label.jpg',
      );
      expect(r.foodRecord.barcode, '9999999999999');
      expect(r.foodRecord.caloriesPer100g, 435); // MockLabelProvider 默认
      // 入库 source=3 verified=0
      final food = await scope.foodsDao.findByBarcode('9999999999999');
      expect(food, isNotNull);
      expect(food!.source, 3);
      expect(food.verified, 0);
      // 二次扫码同条码 → 本地库命中。
      final r2 = await flow.lookup('9999999999999');
      expect(r2, isNotNull);
      expect(r2!.fromCache, isTrue);
    });
  });

  group('RecognitionPipeline：未命中食物 source=2 入库 + sugar 接线', () {
    test('注入 EstimateProvider 后未命中项入库 source=2 verified=0', () async {
      const items = [VisionItem(name: '宫保鸡丁', confidence: 0.6, estGrams: 200)];
      final pipeline = RecognitionPipeline(
        imageProcessor: const MockImageProcessor(),
        vision: const MockVisionProvider(items: items),
        scope: scope,
        daily: daily,
        estimateProvider: const MockEstimateProvider(),
      );
      final result = await pipeline.run('/tmp/x.jpg');
      final it = result.items.single;
      expect(it.foodId, isNotNull); // 已入库 → 有 foodId
      final food = await scope.foodsDao.findById(it.foodId!);
      expect(food, isNotNull);
      expect(food!.source, 2);
      expect(food.verified, 0);
      expect(food.caloriesPer100g, 195); // MockEstimateProvider 宫保鸡丁
      // archiveToday 不再跳过未命中项（已有 foodId）。
      expect(it.calories, closeTo(390, 1)); // 195*2=390
    });

    test('命中项 sugar 从 FoodRecord 接入', () async {
      // 种一条含 sugar 的食物。
      const json = '''
        [{"name":"蛋糕","aliases":[],"calories_per_100g":350,"protein_per_100g":5,"carbs_per_100g":50,"fat_per_100g":10,"sugar_per_100g":25,"source":1}]
      ''';
      await DataScope.ensureSeeded(scope, seedJson: json);
      const items = [VisionItem(name: '蛋糕', confidence: 0.9, estGrams: 100)];
      final pipeline = RecognitionPipeline(
        imageProcessor: const MockImageProcessor(),
        vision: const MockVisionProvider(items: items),
        scope: scope,
        daily: daily,
      );
      final result = await pipeline.run('/tmp/cake.jpg');
      final it = result.items.single;
      expect(it.foodId, isNotNull);
      // 减脂 + sugar 25>20 → R3 红（验证 sugar 已接线，否则会落到 R5 绿）。
      expect(it.signal, Signal.red);
    });

    test('未注入 EstimateProvider → 回退 Task 4 旧行为（营养 0）', () async {
      const items = [VisionItem(name: '未知名菜', confidence: 0.6, estGrams: 200)];
      final pipeline = RecognitionPipeline(
        imageProcessor: const MockImageProcessor(),
        vision: const MockVisionProvider(items: items),
        scope: scope,
        daily: daily,
      );
      final result = await pipeline.run('/tmp/y.jpg');
      final it = result.items.single;
      expect(it.foodId, isNull);
      expect(it.calories, 0);
    });
  });

  group('NutritionLabelProvider（Mock）', () {
    test('解析固定营养表数据', () async {
      const p = MockLabelProvider();
      final r = await p.analyze(
        const ProcessedImage(base64: 'x', dataUrl: 'data:image/jpeg;base64,x'),
      );
      expect(r.name, '某品牌苏打饼干');
      expect(r.caloriesPer100g, 435);
      expect(r.sodiumPer100g, 0.48);
    });

    test('shouldFail → VisionFailedException', () async {
      const p = MockLabelProvider(shouldFail: true);
      expect(
        () => p.analyze(
          const ProcessedImage(
            base64: 'x',
            dataUrl: 'data:image/jpeg;base64,x',
          ),
        ),
        throwsA(isA<VisionFailedException>()),
      );
    });
  });

  group('LabelJsonParser', () {
    test('剥 ``` 后解析', () {
      const raw =
          '```json\n{"name":"饼干","calories_per_100g":435,'
          '"protein_per_100g":8,"carbs_per_100g":64,"fat_per_100g":20}\n```';
      final r = LabelJsonParser.parse(raw);
      expect(r, isNotNull);
      expect(r!.name, '饼干');
      expect(r.caloriesPer100g, 435);
    });

    test('缺 name → null', () {
      const raw = '{"calories_per_100g":100}';
      expect(LabelJsonParser.parse(raw), isNull);
    });

    test('非法 JSON → null', () {
      expect(LabelJsonParser.parse('not json'), isNull);
    });
  });

  group('BarcodeTrafficLight 评估', () {
    test('可乐 330ml（330g）减脂期：糖 10.6<20，热量 139<预算30% → 绿', () {
      final tlr = evaluateBarcodeTrafficLight(
        food: const FoodRecord(
          id: 1,
          name: '可口可乐',
          aliasesJson: '[]',
          caloriesPer100g: 42,
          proteinPer100g: 0,
          carbsPer100g: 10.6,
          fatPer100g: 0,
          sugarPer100g: 10.6,
          barcode: '5449000000997',
        ),
        grams: 330,
        daily: daily,
      );
      expect(tlr.signal, Signal.green);
    });
  });

  group('archiveBarcodeEntry 写库', () {
    test('写一条 meal_entries + 即时刷新首页', () async {
      // 先建档 + 加一个食物。
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
      final fid = await scope.foodsDao.addOne(
        FoodsCompanion.insert(
          name: '可乐',
          aliases: const Value('[]'),
          caloriesPer100g: 42,
          proteinPer100g: 0,
          carbsPer100g: 10.6,
          fatPer100g: 0,
          source: 3,
          barcode: const Value('5449000000997'),
        ),
      );
      final id = await archiveBarcodeEntry(
        scope: scope,
        foodId: fid,
        grams: 330,
        mealType: 4,
        calories: 138.6,
        protein: 0,
        carbs: 34.98,
        fat: 0,
      );
      expect(id, greaterThan(0));
      // 首页即时刷新看到这条。
      await scope.homeView.refresh();
      expect(scope.homeView.consumedCalories, closeTo(138.6, 1));
      expect(scope.homeView.todayGroups.single.mealType, 4);
    });
  });
}
