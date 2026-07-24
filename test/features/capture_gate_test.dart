// 拍食记 Task 3 DoD widget 测试：
// 1) 无 DashScope key 时 CapturePage 显示引导页（而非报错/拍照按钮）。
// 2) 有 key 时显示拍照占位。
// 3) 错误 key 经 ConnectionTester 返回"密钥无效"文案。
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/core/app_services.dart';
import 'package:paishiji/data/data.dart';
import 'package:paishiji/data/providers/connection_tester.dart';
import 'package:paishiji/data/providers/key_vault.dart';
import 'package:paishiji/features/capture/capture_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  AppServices newServices({String? dashKey, String? glmKey}) {
    final scope = DataScope(AppDatabase.forTesting(null));
    final vault = MemoryKeyVault();
    if (dashKey != null) vault.write(ApiKeyType.dashscope, dashKey);
    if (glmKey != null) vault.write(ApiKeyType.glm, glmKey);
    final svc = AppServices.forTesting(scope, vault, MockConnectionTester());
    return svc;
  }

  group('CapturePage — DoD：无 key 显示引导页而非报错', () {
    testWidgets('无 DashScope key → 引导卡（含"去设置"按钮，不含拍照按钮）', (tester) async {
      final svc = newServices(); // 无 key
      await tester.pumpWidget(MaterialApp(home: CapturePage(services: svc)));
      await tester.pump();
      expect(find.text('尚未配置 API Key'), findsOneWidget);
      expect(find.text('去设置'), findsOneWidget);
      expect(find.text('拍照'), findsNothing); // 不展示拍照入口
      expect(find.text('从相册选择'), findsNothing);
    });

    testWidgets('有 DashScope key → 拍照占位（含拍照/相册按钮）', (tester) async {
      final svc = newServices(dashKey: 'sk-valid');
      await tester.pumpWidget(MaterialApp(home: CapturePage(services: svc)));
      await tester.pump();
      expect(find.text('点按下方按钮拍摄餐盘'), findsOneWidget);
      expect(find.text('拍照'), findsOneWidget);
      expect(find.text('从相册选择'), findsOneWidget);
      expect(find.text('尚未配置 API Key'), findsNothing);
    });
  });

  group('ConnectionTester — DoD：错误 key 提示"密钥无效"', () {
    test('bad key 经 tester 返回密钥无效', () async {
      final svc = newServices(dashKey: 'bad');
      final r = await svc.tester.testDashScope('bad');
      expect(r.outcome, KeyTestOutcome.invalid);
      expect(r.display, contains('密钥无效'));
    });
  });

  group('AppServices.hasDashScopeKey 联动', () {
    test('无 key → false；保存后 → true；删除后 → false', () async {
      final svc = newServices();
      expect(svc.hasDashScopeKey, isFalse);
      await svc.keyVault.write(ApiKeyType.dashscope, 'sk-abc');
      await svc.onKeyChanged();
      expect(svc.hasDashScopeKey, isTrue);
      await svc.keyVault.write(ApiKeyType.dashscope, '');
      await svc.onKeyChanged();
      expect(svc.hasDashScopeKey, isFalse);
    });
  });
}
