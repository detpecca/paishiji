// 拍食记 ConnectionTester 单测。Mock 各分支：valid / invalid / networkError。
// 红线#2：零真实 API 调用。
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/data/providers/connection_tester.dart';
import 'package:paishiji/data/providers/key_vault.dart';

void main() {
  late MockConnectionTester tester;

  setUp(() => tester = MockConnectionTester());

  group('MockConnectionTester — DashScope', () {
    test('空 key → invalid', () async {
      final r = await tester.testDashScope('');
      expect(r.outcome, KeyTestOutcome.invalid);
    });
    test('bad key → invalid（DoD：错误 key 提示密钥无效）', () async {
      final r = await tester.testDashScope('bad');
      expect(r.outcome, KeyTestOutcome.invalid);
      expect(r.display, contains('密钥无效'));
    });
    test('net-error key → networkError', () async {
      final r = await tester.testDashScope('net-error');
      expect(r.outcome, KeyTestOutcome.networkError);
      expect(r.display, contains('网络异常'));
    });
    test('正常 key → valid', () async {
      final r = await tester.testDashScope('sk-valid-123');
      expect(r.outcome, KeyTestOutcome.valid);
      expect(r.display, '密钥有效');
    });
  });

  group('MockConnectionTester — GLM（对称）', () {
    test('bad → invalid', () async {
      final r = await tester.testGlm('bad');
      expect(r.outcome, KeyTestOutcome.invalid);
    });
    test('正常 → valid', () async {
      final r = await tester.testGlm('glm-valid');
      expect(r.outcome, KeyTestOutcome.valid);
    });
  });

  group('MockConnectionTester — Custom（Kimi 等）', () {
    test('配置不完整（apiKey 空）→ invalid', () async {
      final r = await tester.testCustom(
        const CustomProviderConfig(baseUrl: 'https://x', model: 'm', apiKey: ''),
      );
      expect(r.outcome, KeyTestOutcome.invalid);
    });
    test('bad key → invalid', () async {
      final r = await tester.testCustom(
        const CustomProviderConfig(
          baseUrl: 'https://x',
          model: 'm',
          apiKey: 'bad',
        ),
      );
      expect(r.outcome, KeyTestOutcome.invalid);
    });
    test('net-error key → networkError', () async {
      final r = await tester.testCustom(
        const CustomProviderConfig(
          baseUrl: 'https://x',
          model: 'm',
          apiKey: 'net-error',
        ),
      );
      expect(r.outcome, KeyTestOutcome.networkError);
    });
    test('正常完整配置 → valid', () async {
      final r = await tester.testCustom(
        const CustomProviderConfig(
          baseUrl: 'https://api.kimi.com/coding/v1',
          model: 'kimi-k2.7-code',
          apiKey: 'sk-valid',
        ),
      );
      expect(r.outcome, KeyTestOutcome.valid);
      expect(r.display, '密钥有效');
    });
  });

  group('KeyTestResult.display 文案', () {
    test('invalid 明确含"密钥无效"', () {
      const r = KeyTestResult(KeyTestOutcome.invalid);
      expect(r.display, '密钥无效，请检查 API Key');
    });
    test('networkError 含"网络异常"且可选 detail', () {
      const r = KeyTestResult(KeyTestOutcome.networkError, 'timeout');
      expect(r.display, contains('网络异常'));
      expect(r.display, contains('timeout'));
    });
    test('valid 文案稳定', () {
      const r = KeyTestResult(KeyTestOutcome.valid);
      expect(r.display, '密钥有效');
      expect(r.isValid, isTrue);
    });
  });
}

