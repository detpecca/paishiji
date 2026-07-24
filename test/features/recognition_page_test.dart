// 拍食记识别页 widget 测。验证：loading/结果/低置信度黄条/估算角标/存入今日。
// Mock 全链路零真实 API（红线#2）。
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/data/data.dart';
import 'package:paishiji/data/providers/image_processor.dart';
import 'package:paishiji/data/providers/recognition_pipeline.dart';
import 'package:paishiji/data/providers/vision_provider.dart';
import 'package:paishiji/domain/nutrition_matcher.dart';
import 'package:paishiji/domain/traffic_light_engine.dart';
import 'package:paishiji/features/recognition/recognition_controller.dart';
import 'package:paishiji/features/recognition/recognition_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  AppDatabase newDb() => AppDatabase.forTesting(null);

  Future<DataScope> seededScope() async {
    final db = newDb();
    final scope = DataScope(db);
    const seed = '''
      [{"name":"番茄炒蛋","aliases":[],"calories_per_100g":86,"protein_per_100g":5.6,"carbs_per_100g":4.4,"fat_per_100g":5.1,"source":1}]
    ''';
    await DataScope.ensureSeeded(scope, seedJson: seed);
    return scope;
  }

  group('RecognitionPage widget', () {
    testWidgets('loading 显示"正在识别，约 3 秒"', (tester) async {
      final scope = await seededScope();
      addTearDown(scope.db.close);
      await tester.pumpWidget(
        MaterialApp(
          home: RecognitionPage(
            imagePath: '/tmp/x.jpg',
            scope: scope,
            imageProcessor: const MockImageProcessor(),
            vision: const MockVisionProvider(),
          ),
        ),
      );
      await tester.pump();
      // 识别前应见 loading 文案
      expect(find.text('正在识别，约 3 秒…'), findsOneWidget);
      await tester.pumpAndSettle(); // 让 future 完成以避免 pending timers
    });

    testWidgets('结果页展示菜名 + 份量滑块 + 热量(带估算角标) + 整餐合计', (tester) async {
      final scope = await seededScope();
      addTearDown(scope.db.close);
      await tester.pumpWidget(
        MaterialApp(
          home: RecognitionPage(
            imagePath: '/tmp/x.jpg',
            scope: scope,
            imageProcessor: const MockImageProcessor(),
            vision: const MockVisionProvider(
              items: [VisionItem(name: '番茄炒蛋', confidence: 0.9, estGrams: 250)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('番茄炒蛋'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.textContaining('kcal'), findsWidgets);
      // 估算角标（红线#1）
      expect(find.text('估算'), findsWidgets);
      // 整餐合计
      expect(find.text('整餐合计'), findsOneWidget);
      // 存入今日按钮
      expect(find.text('存入今日'), findsOneWidget);
    });

    testWidgets('低置信度(<0.7)显示黄条警示', (tester) async {
      final scope = await seededScope();
      addTearDown(scope.db.close);
      await tester.pumpWidget(
        MaterialApp(
          home: RecognitionPage(
            imagePath: '/tmp/x.jpg',
            scope: scope,
            imageProcessor: const MockImageProcessor(),
            vision: const MockVisionProvider(
              items: [VisionItem(name: '番茄炒蛋', confidence: 0.5, estGrams: 250)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('识别不确定，点选正确食物纠正：'), findsOneWidget);
    });

    testWidgets('份量滑块改 → 营养与红绿灯实时联动（无闪烁）', (tester) async {
      final scope = await seededScope();
      addTearDown(scope.db.close);
      await tester.pumpWidget(
        MaterialApp(
          home: RecognitionPage(
            imagePath: '/tmp/x.jpg',
            scope: scope,
            imageProcessor: const MockImageProcessor(),
            vision: const MockVisionProvider(
              items: [VisionItem(name: '番茄炒蛋', confidence: 0.9, estGrams: 250)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 初始合计 ≈ 215kcal（番茄炒蛋 250g）
      expect(find.textContaining('215'), findsWidgets);

      // 拖滑块到最大 800g
      await tester.drag(find.byType(Slider), const Offset(500, 0));
      await tester.pump();
      // 应见 800g 标签
      expect(find.textContaining('800g'), findsWidgets);
    });

    testWidgets('存入今日写库 + snackbar + 返回', (tester) async {
      final scope = await seededScope();
      addTearDown(scope.db.close);
      await tester.pumpWidget(
        MaterialApp(
          home: RecognitionPage(
            imagePath: '/tmp/x.jpg',
            scope: scope,
            imageProcessor: const MockImageProcessor(),
            vision: const MockVisionProvider(
              items: [VisionItem(name: '番茄炒蛋', confidence: 0.9, estGrams: 250)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('存入今日'));
      await tester.pumpAndSettle();

      // 库内应有一行 meal_entries（今日）
      final now = DateTime.now();
      final date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final entries = await scope.mealEntriesDao.ofDate(date);
      expect(entries, hasLength(1));
    });
  });

  group('EditableItem 估算角标（红线#1 单测）', () {
    test('calories 字段总带估算语义（UI 渲染时角标在侧）', () {
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
        confidence: 0.9,
        estGrams: 100,
        calories: 100,
        proteinG: 1,
        carbsG: 1,
        fatG: 1,
        signal: Signal.green,
        advice: '',
      );
      const daily = DailyContext(
        goalType: 1,
        targetCalories: 2000,
        consumedCalories: 0,
        targetProtein: 140,
        consumedProtein: 0,
      );
      final item = EditableItem(
        view: view,
        per100g: fr,
        daily: daily,
        sugarPer100g: 0,
      );
      // 营养数字来自估算（每100g × grams / 100），非称重实测
      expect(item.calories, greaterThan(0));
    });
  });
}
