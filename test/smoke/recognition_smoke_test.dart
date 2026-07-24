// 拍食记识别 smoke —— 以 flutter test 形式运行。
// CLAUDE.md §六 Task 4 DoD：tool/recognition_smoke.dart 用 fixtures 照片跑通。
// 因 dart run 在 Windows 对 sqlite3 FFI 有编译 bug，smoke 改走 flutter test 编译管线。
//
// Mock 模式（默认）：零真实 API、不依赖 fixtures，走完整 pipeline 验结构。
// Real 模式：设环境变量 PAISHIJI_SMOKE_REAL=1 + DASHSCOPE_API_KEY + test/fixtures/ 照片。
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/core/constants.dart';
import 'package:paishiji/data/data.dart';
import 'package:paishiji/data/providers/image_processor.dart';
import 'package:paishiji/data/providers/recognition_pipeline.dart';
import 'package:paishiji/data/providers/vision_provider.dart';
import 'package:paishiji/domain/traffic_light_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final useReal = Platform.environment['PAISHIJI_SMOKE_REAL'] == '1';

  test('recognition smoke：pipeline 结构合法', () async {
    final db = AppDatabase.forTesting(null);
    final scope = DataScope(db);
    addTearDown(db.close);

    final assetFile = File('assets/seed_foods.json');
    if (await assetFile.exists()) {
      await DataScope.ensureSeeded(
        scope,
        seedJson: await assetFile.readAsString(),
      );
    }

    const daily = DailyContext(
      goalType: 1,
      targetCalories: 1751,
      consumedCalories: 0,
      targetProtein: 140,
      consumedProtein: 0,
    );

    final VisionProvider vision;
    final ImageProcessor processor;
    if (useReal) {
      final key = Platform.environment['DASHSCOPE_API_KEY'] ?? '';
      expect(key, isNotEmpty, reason: 'real 模式需 DASHSCOPE_API_KEY');
      vision = VisionChain(primary: QwenVisionProvider(apiKey: key));
      processor = const DartImageProcessor();
    } else {
      vision = MockVisionProvider();
      processor = const MockImageProcessor();
    }

    final pipeline = RecognitionPipeline(
      imageProcessor: processor,
      vision: vision,
      scope: scope,
      daily: daily,
    );

    final dir = Directory('test/fixtures');
    final files = await dir.exists()
        ? dir
              .listSync()
              .whereType<File>()
              .where(
                (f) =>
                    f.path.endsWith('.jpg') ||
                    f.path.endsWith('.jpeg') ||
                    f.path.endsWith('.png'),
              )
              .toList()
        : <File>[];

    if (useReal && files.isEmpty) {
      fail('real 模式需 test/fixtures/ 下放中餐照片');
    }

    // Mock 模式无 fixtures：用合成路径跑一次
    if (files.isEmpty) {
      final r = await pipeline.run('mock://no-fixture.jpg');
      _print('mock-no-fixture', r);
      expect(r.items, isNotEmpty);
      expect(r.items.length, lessThanOrEqualTo(AppConstants.visionMaxItems));
      return;
    }

    var ok = 0;
    for (final f in files) {
      try {
        final r = await pipeline.run(f.path, imageFile: f);
        _print(f.path, r);
        expect(r.items.length, lessThanOrEqualTo(AppConstants.visionMaxItems));
        ok++;
      } catch (e) {
        // ignore: avoid_print
        print('${f.path} 失败: $e');
      }
    }
    // ignore: avoid_print
    print('\n$ok/${files.length} 张通过');
    expect(ok, files.length);
  });
}

void _print(String label, RecognitionResultView r) {
  // ignore: avoid_print
  print('=== $label ===');
  // ignore: avoid_print
  print(
    'provider=${r.provider} latency=${r.latencyMs}ms 总热量≈${r.totalCalories.round()}kcal',
  );
  for (final it in r.items) {
    // ignore: avoid_print
    print(
      '  ${it.signal.emoji} ${it.detectedName} | ${it.estGrams}g | '
      '≈${it.calories.round()}kcal P${it.proteinG.round()} C${it.carbsG.round()} F${it.fatG.round()} | '
      'conf=${it.confidence.toStringAsFixed(2)} | ${it.advice}',
    );
  }
}
