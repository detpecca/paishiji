// 拍食记 Task 3 DoD widget 测试：
// 1) 无 DashScope key 时 CapturePage 显示引导页（而非报错/拍照按钮）。
// 2) 有 key 时显示拍照占位。
// 3) 错误 key 经 ConnectionTester 返回"密钥无效"文案。
// 4) 自定义 provider 配置完整时也算"有 key"，闸门放行。
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

  Future<AppServices> newServices({
    String? dashKey,
    String? glmKey,
    CustomProviderConfig? custom,
  }) async {
    final scope = DataScope(AppDatabase.forTesting(null));
    final vault = MemoryKeyVault();
    if (dashKey != null) await vault.write(ApiKeyType.dashscope, dashKey);
    if (glmKey != null) await vault.write(ApiKeyType.glm, glmKey);
    if (custom != null) {
      await vault.write(ApiKeyType.custom, custom.toJsonString());
    }
    final svc = AppServices.forTesting(scope, vault, MockConnectionTester());
    // forTesting 构造里 _refreshKeyState 是 fire-and-forget；显式 await 一次确保
    // cachedVision / hasVisionKey 就绪后再返回。
    await svc.onKeyChanged();
    return svc;
  }

  group('CapturePage — DoD：无 key 显示引导页而非报错', () {
    testWidgets('无 DashScope key 且无自定义 → 引导卡（含"去设置"，不含拍照）', (tester) async {
      final svc = await newServices(); // 无 key
      await tester.pumpWidget(MaterialApp(home: CapturePage(services: svc)));
      await tester.pump();
      expect(find.text('尚未配置 API Key'), findsOneWidget);
      expect(find.text('去设置'), findsOneWidget);
      expect(find.text('拍照'), findsNothing); // 不展示拍照入口
      expect(find.text('从相册选择'), findsNothing);
    });

    testWidgets('有 DashScope key → 拍照占位（含拍照/相册按钮）', (tester) async {
      final svc = await newServices(dashKey: 'sk-valid');
      await tester.pumpWidget(MaterialApp(home: CapturePage(services: svc)));
      await tester.pump();
      expect(find.text('点按下方按钮拍摄餐盘'), findsOneWidget);
      expect(find.text('拍照'), findsOneWidget);
      expect(find.text('从相册选择'), findsOneWidget);
      expect(find.text('尚未配置 API Key'), findsNothing);
    });

    testWidgets('只有自定义 provider 完整 → 拍照占位（闸门 hasVisionKey 放行）', (tester) async {
      final svc = await newServices(
        custom: const CustomProviderConfig(
          baseUrl: 'https://api.kimi.com/coding/v1',
          model: 'kimi-k2.7-code',
          apiKey: 'sk-kimi',
        ),
      );
      expect(svc.hasDashScopeKey, isFalse); // 没有 DashScope
      expect(svc.hasVisionKey, isTrue); // 但有自定义 → 闸门放行
      await tester.pumpWidget(MaterialApp(home: CapturePage(services: svc)));
      await tester.pump();
      expect(find.text('拍照'), findsOneWidget);
      expect(find.text('尚未配置 API Key'), findsNothing);
    });

    testWidgets('自定义配置不完整（缺 apiKey）→ 闸门不放行', (tester) async {
      final svc = await newServices(
        custom: const CustomProviderConfig(
          baseUrl: 'https://x',
          model: 'm',
          apiKey: '',
        ),
      );
      expect(svc.hasVisionKey, isFalse);
      await tester.pumpWidget(MaterialApp(home: CapturePage(services: svc)));
      await tester.pump();
      expect(find.text('尚未配置 API Key'), findsOneWidget);
    });
  });

  group('ConnectionTester — DoD：错误 key 提示"密钥无效"', () {
    test('bad key 经 tester 返回密钥无效', () async {
      final svc = await newServices(dashKey: 'bad');
      final r = await svc.tester.testDashScope('bad');
      expect(r.outcome, KeyTestOutcome.invalid);
      expect(r.display, contains('密钥无效'));
    });
  });

  group('AppServices key 状态联动', () {
    test('DashScope：无→保存→删除', () async {
      final svc = await newServices();
      expect(svc.hasDashScopeKey, isFalse);
      await svc.keyVault.write(ApiKeyType.dashscope, 'sk-abc');
      await svc.onKeyChanged();
      expect(svc.hasDashScopeKey, isTrue);
      await svc.keyVault.write(ApiKeyType.dashscope, '');
      await svc.onKeyChanged();
      expect(svc.hasDashScopeKey, isFalse);
    });

    test('自定义：保存完整配置 → hasVisionKey=true + cachedVision 非空', () async {
      final svc = await newServices();
      expect(svc.hasVisionKey, isFalse);
      expect(svc.cachedVision, isNull);
      await svc.keyVault.write(
        ApiKeyType.custom,
        const CustomProviderConfig(
          baseUrl: 'https://api.kimi.com/coding/v1',
          model: 'kimi-k2.7-code',
          apiKey: 'sk-kimi',
        ).toJsonString(),
      );
      await svc.onKeyChanged();
      expect(svc.hasCustomProvider, isTrue);
      expect(svc.hasVisionKey, isTrue);
      expect(svc.cachedVision, isNotNull);
      expect(svc.cachedLabel, isNotNull);
      expect(svc.cachedEstimate, isNotNull);
    });

    test('降级链：自定义 + DashScope 都填 → cachedVision 主是 Custom', () async {
      final svc = await newServices(
        dashKey: 'sk-dash',
        custom: const CustomProviderConfig(
          baseUrl: 'https://api.kimi.com/coding/v1',
          model: 'kimi-k2.7-code',
          apiKey: 'sk-kimi',
        ),
      );
      final vision = svc.cachedVision!;
      // VisionChain.name 形如 "chain(custom:kimi-k2.7-code/...)"
      expect(vision.name, contains('custom:kimi'));
    });

    test('只有 DashScope → cachedVision 主是 Qwen', () async {
      final svc = await newServices(dashKey: 'sk-dash');
      final vision = svc.cachedVision!;
      expect(vision.name, contains('qwen'));
    });
  });
}
