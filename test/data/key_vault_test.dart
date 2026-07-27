// 拍食记 KeyVault 单测。内存实现 + 抽象契约。零 secure_storage 插件依赖。
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/data/providers/key_vault.dart';

void main() {
  late MemoryKeyVault vault;

  setUp(() => vault = MemoryKeyVault());

  group('MemoryKeyVault', () {
    test('读未写的 key 返回 null', () async {
      expect(await vault.read(ApiKeyType.dashscope), isNull);
      expect(await vault.read(ApiKeyType.glm), isNull);
    });

    test('write 后可 read 回', () async {
      await vault.write(ApiKeyType.dashscope, 'sk-abc');
      expect(await vault.read(ApiKeyType.dashscope), 'sk-abc');
    });

    test('write null 或空串视为删除（防止明文残留）', () async {
      await vault.write(ApiKeyType.dashscope, 'sk-abc');
      expect(await vault.read(ApiKeyType.dashscope), 'sk-abc');
      await vault.write(ApiKeyType.dashscope, null);
      expect(await vault.read(ApiKeyType.dashscope), isNull);
      await vault.write(ApiKeyType.glm, 'glm-1');
      await vault.write(ApiKeyType.glm, '');
      expect(await vault.read(ApiKeyType.glm), isNull);
    });

    test('delete 显式删除', () async {
      await vault.write(ApiKeyType.dashscope, 'sk-abc');
      await vault.delete(ApiKeyType.dashscope);
      expect(await vault.read(ApiKeyType.dashscope), isNull);
    });

    test('readAll 只返回非空 key', () async {
      await vault.write(ApiKeyType.dashscope, 'sk-abc');
      final all = await vault.readAll();
      expect(all, hasLength(1));
      expect(all[ApiKeyType.dashscope], 'sk-abc');
      expect(all.containsKey(ApiKeyType.glm), isFalse);
      await vault.write(ApiKeyType.glm, 'glm-1');
      final all2 = await vault.readAll();
      expect(all2, hasLength(2));
    });

    test('两把 key 互不串扰', () async {
      await vault.write(ApiKeyType.dashscope, 'sk-dash');
      await vault.write(ApiKeyType.glm, 'glm-glm');
      expect(await vault.read(ApiKeyType.dashscope), 'sk-dash');
      expect(await vault.read(ApiKeyType.glm), 'glm-glm');
    });
  });

  group('CustomProviderConfig', () {
    test('tryParse 合法 JSON → 三字段正确', () {
      const raw = '{"baseUrl":"https://api.kimi.com/coding/v1","model":"kimi-k2.7-code","apiKey":"sk-1"}';
      final cfg = CustomProviderConfig.tryParse(raw);
      expect(cfg, isNotNull);
      expect(cfg!.baseUrl, 'https://api.kimi.com/coding/v1');
      expect(cfg.model, 'kimi-k2.7-code');
      expect(cfg.apiKey, 'sk-1');
      expect(cfg.isComplete, isTrue);
    });

    test('tryParse null / 空串 → null', () {
      expect(CustomProviderConfig.tryParse(null), isNull);
      expect(CustomProviderConfig.tryParse(''), isNull);
      expect(CustomProviderConfig.tryParse('   '), isNull);
    });

    test('tryParse 非 JSON → null', () {
      expect(CustomProviderConfig.tryParse('not json'), isNull);
    });

    test('tryParse 缺字段 → null', () {
      // 缺 apiKey
      expect(
        CustomProviderConfig.tryParse('{"baseUrl":"x","model":"y"}'),
        isNull,
      );
    });

    test('isComplete：任一字段空 → false', () {
      const cfg = CustomProviderConfig(baseUrl: '', model: 'm', apiKey: 'k');
      expect(cfg.isComplete, isFalse);
    });

    test('toJsonString → tryParse 往返', () {
      const cfg = CustomProviderConfig(
        baseUrl: 'https://x',
        model: 'm',
        apiKey: 'k',
      );
      final parsed = CustomProviderConfig.tryParse(cfg.toJsonString());
      expect(parsed, isNotNull);
      expect(parsed!.baseUrl, 'https://x');
      expect(parsed.model, 'm');
      expect(parsed.apiKey, 'k');
    });
  });

  group('MemoryKeyVault custom 档', () {
    test('custom 档 read/write/delete 同 dashscope', () async {
      expect(await vault.read(ApiKeyType.custom), isNull);
      await vault.write(ApiKeyType.custom, '{"baseUrl":"x","model":"y","apiKey":"z"}');
      expect(
        await vault.read(ApiKeyType.custom),
        '{"baseUrl":"x","model":"y","apiKey":"z"}',
      );
      await vault.write(ApiKeyType.custom, null);
      expect(await vault.read(ApiKeyType.custom), isNull);
    });

    test('readAll 含 custom 档', () async {
      await vault.write(ApiKeyType.dashscope, 'sk');
      await vault.write(
        ApiKeyType.custom,
        '{"baseUrl":"x","model":"y","apiKey":"z"}',
      );
      final all = await vault.readAll();
      expect(all, hasLength(2));
      expect(all.containsKey(ApiKeyType.custom), isTrue);
    });
  });
}
