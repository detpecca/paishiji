// 拍食记识别 pipeline 端到端单测。Mock 全链路，零真实 API（红线#2）。
// 验证：压缩→识别→匹配→红绿灯→写库 结构合法。
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/data/data.dart';
import 'package:paishiji/data/providers/image_processor.dart';
import 'package:paishiji/data/providers/recognition_pipeline.dart';
import 'package:paishiji/data/providers/vision_provider.dart';
import 'package:paishiji/domain/traffic_light_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DataScope scope;

  setUp(() async {
    db = AppDatabase.forTesting(null);
    scope = DataScope(db);
    // 灌入种子，让匹配能命中"番茄炒蛋""米饭"
    const json = '''
      [{"name":"番茄炒蛋","aliases":["西红柿炒蛋"],"calories_per_100g":86,"protein_per_100g":5.6,"carbs_per_100g":4.4,"fat_per_100g":5.1,"source":1},
       {"name":"米饭","aliases":[],"calories_per_100g":116,"protein_per_100g":2.6,"carbs_per_100g":25.9,"fat_per_100g":0.3,"source":1}]
    ''';
    await DataScope.ensureSeeded(scope, seedJson: json);
  });

  tearDown(() => db.close());

  group('RecognitionPipeline（Mock 全链路）', () {
    test('正常路径：2 项识别 + 写库 + 红绿灯', () async {
      const daily = DailyContext(
        goalType: 1,
        targetCalories: 1751,
        consumedCalories: 0,
        targetProtein: 140,
        consumedProtein: 0,
      );
      final pipeline = RecognitionPipeline(
        imageProcessor: const MockImageProcessor(),
        vision: const MockVisionProvider(), // 默认返回 番茄炒蛋 + 米饭
        scope: scope,
        daily: daily,
      );
      final result = await pipeline.run('/tmp/fake.jpg');

      expect(result.items, hasLength(2));
      expect(result.recognitionId, greaterThan(0));
      expect(result.provider, 'mock');

      // 番茄炒蛋 250g：86*2.5=215kcal。减脂期，糖4.4/脂5.1 都不超20，蛋白5.6<15 不触发R4
      // 215/1751≈12%<30% → R5 绿
      final tomato = result.items.firstWhere((i) => i.detectedName == '番茄炒蛋');
      expect(tomato.signal, Signal.green);
      expect(tomato.calories, closeTo(215, 0.5));
      expect(tomato.foodId, isNotNull); // 命中种子库

      // 米饭 200g：116*2=232kcal。糖0脂0.3，蛋白2.6<15。232/1751≈13%<30% → R5 绿
      final rice = result.items.firstWhere((i) => i.detectedName == '米饭');
      expect(rice.signal, Signal.green);
      expect(rice.calories, closeTo(232, 0.5));

      // 库内 recognitions + recognition_items 各写 1 / 2 行
      final itemsInDb = await scope.recognitionsDao.itemsOf(
        result.recognitionId,
      );
      expect(itemsInDb, hasLength(2));
      expect(result.totalCalories, closeTo(447, 1));
    });

    test('未命中库的食物：foodId=null，营养 0', () async {
      const daily = DailyContext(
        goalType: 1,
        targetCalories: 1751,
        consumedCalories: 0,
        targetProtein: 140,
        consumedProtein: 0,
      );
      const customItems = [
        VisionItem(name: '未知名菜', confidence: 0.6, estGrams: 200),
      ];
      final pipeline = RecognitionPipeline(
        imageProcessor: const MockImageProcessor(),
        vision: const MockVisionProvider(items: customItems),
        scope: scope,
        daily: daily,
      );
      final result = await pipeline.run('/tmp/x.jpg');
      expect(result.items, hasLength(1));
      final it = result.items.single;
      expect(it.foodId, isNull); // 未命中
      expect(it.calories, 0); // 营养暂置 0
      // 未命中 + 营养0：糖0脂0不触发R3；蛋白0<15 不R4；cal0/1751=0%<30%→R5绿
      expect(it.signal, Signal.green);
    });

    test('主 provider 故障 → VisionChain 降级到备', () async {
      const daily = DailyContext(
        goalType: 1,
        targetCalories: 1751,
        consumedCalories: 0,
        targetProtein: 140,
        consumedProtein: 0,
      );
      final pipeline = RecognitionPipeline(
        imageProcessor: const MockImageProcessor(),
        vision: const VisionChain(
          primary: MockVisionProvider(shouldFail: true),
          fallback: MockVisionProvider(),
        ),
        scope: scope,
        daily: daily,
      );
      final result = await pipeline.run('/tmp/y.jpg');
      expect(result.items, hasLength(2)); // 备 provider 的默认 2 项
    });

    test('匹配链 FoodRecord 投影正确（aliases 解析）', () async {
      // 间接验证 NutritionMatcher 在 pipeline 里能读 aliases
      const daily = DailyContext(
        goalType: 1,
        targetCalories: 2000,
        consumedCalories: 0,
        targetProtein: 140,
        consumedProtein: 0,
      );
      const items = [VisionItem(name: '西红柿炒蛋', confidence: 0.9, estGrams: 250)];
      final pipeline = RecognitionPipeline(
        imageProcessor: const MockImageProcessor(),
        vision: const MockVisionProvider(items: items),
        scope: scope,
        daily: daily,
      );
      final result = await pipeline.run('/tmp/alias.jpg');
      expect(result.items.single.detectedName, '西红柿炒蛋');
      // 通过 alias 命中"番茄炒蛋"
      expect(result.items.single.foodId, isNotNull);
    });
  });
}
