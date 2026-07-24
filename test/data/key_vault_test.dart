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
}
