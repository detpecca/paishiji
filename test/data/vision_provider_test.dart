// 拍食记 VisionProvider 单测。Mock + 降级链各分支 + JSON 解析。
// 红线#2：零真实 API 调用。
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/core/app_exceptions.dart';
import 'package:paishiji/data/providers/image_processor.dart';
import 'package:paishiji/data/providers/vision_provider.dart';

void main() {
  const image = ProcessedImage(
    base64: 'mock',
    dataUrl: 'data:image/jpeg;base64,mock',
    width: 100,
    height: 100,
  );

  group('MockVisionProvider', () {
    test('默认返回 2 项', () async {
      final items = await const MockVisionProvider().analyze(image);
      expect(items, hasLength(2));
      expect(items.first.name, '番茄炒蛋');
      expect(items.last.name, '米饭');
    });

    test('shouldFail 抛 VisionFailedException', () async {
      const p = MockVisionProvider(shouldFail: true);
      expect(() => p.analyze(image), throwsA(isA<VisionFailedException>()));
    });

    test('自定义 items 原样返回', () async {
      const items = [VisionItem(name: 'X', confidence: 0.5, estGrams: 100)];
      const p = MockVisionProvider(items: items);
      expect(await p.analyze(image), items);
    });
  });

  group('VisionChain 降级链', () {
    test('主成功 → 用主结果', () async {
      const chain = VisionChain(
        primary: MockVisionProvider(),
        fallback: MockVisionProvider(shouldFail: true),
      );
      final items = await chain.analyze(image);
      expect(items, hasLength(2));
    });

    test('主故障 + 备成功 → 用备结果', () async {
      const chain = VisionChain(
        primary: MockVisionProvider(shouldFail: true),
        fallback: MockVisionProvider(),
      );
      final items = await chain.analyze(image);
      expect(items, hasLength(2));
    });

    test('主故障 + 无备 → 抛友好错误', () async {
      const chain = VisionChain(primary: MockVisionProvider(shouldFail: true));
      expect(() => chain.analyze(image), throwsA(isA<VisionFailedException>()));
    });

    test('主故障 + 备故障 → 抛友好错误', () async {
      const chain = VisionChain(
        primary: MockVisionProvider(shouldFail: true),
        fallback: MockVisionProvider(shouldFail: true),
      );
      expect(() => chain.analyze(image), throwsA(isA<VisionFailedException>()));
    });

    test('主抛 InvalidKeyException → 直接抛不走降级', () async {
      // 用一个抛 InvalidKey 的伪 provider
      final chain = VisionChain(
        primary: _ThrowingProvider(const InvalidKeyException()),
        fallback: const MockVisionProvider(),
      );
      expect(() => chain.analyze(image), throwsA(isA<InvalidKeyException>()));
    });
  });

  group('VisionJsonParser', () {
    test('严格 JSON 数组', () {
      final items = VisionJsonParser.parse(
        '[{"name":"番茄炒蛋","confidence":0.9,"est_grams":250,"ingredients":["番茄","鸡蛋"]}]',
      );
      expect(items, hasLength(1));
      expect(items.single.name, '番茄炒蛋');
      expect(items.single.confidence, 0.9);
      expect(items.single.estGrams, 250);
      expect(items.single.ingredients, ['番茄', '鸡蛋']);
    });

    test('带 ``` 代码块包裹', () {
      final items = VisionJsonParser.parse(
        '```json\n[{"name":"米饭","confidence":0.95,"est_grams":200}]\n```',
      );
      expect(items, hasLength(1));
      expect(items.single.name, '米饭');
    });

    test('前后有多余文字（抽取第一个 [..]）', () {
      final items = VisionJsonParser.parse(
        '识别结果如下：\n[{"name":"面条","confidence":0.8,"est_grams":250}]\n以上。',
      );
      expect(items, hasLength(1));
      expect(items.single.name, '面条');
    });

    test('空串 → 空', () {
      expect(VisionJsonParser.parse(''), isEmpty);
    });

    test('非法 JSON → 空', () {
      expect(VisionJsonParser.parse('[not json'), isEmpty);
    });

    test('缺字段用默认（confidence/grams 兜底 0）', () {
      final items = VisionJsonParser.parse('[{"name":"汤"}]');
      expect(items, hasLength(1));
      expect(items.single.name, '汤');
      expect(items.single.confidence, 0.0);
      expect(items.single.estGrams, 0);
    });

    test('跳过无 name 项', () {
      final items = VisionJsonParser.parse(
        '[{"confidence":0.5},{"name":"有效","confidence":0.9,"est_grams":100}]',
      );
      expect(items, hasLength(1));
      expect(items.single.name, '有效');
    });

    test('estGrams camelCase 兼容', () {
      final items = VisionJsonParser.parse('[{"name":"x","estGrams":150}]');
      expect(items.single.estGrams, 150);
    });
  });
}

/// 抛指定异常的伪 provider（测降级链对 InvalidKey 的特殊处理）。
class _ThrowingProvider implements VisionProvider {
  _ThrowingProvider(this.error);
  final Object error;

  @override
  String get name => 'thrower';

  @override
  Future<List<VisionItem>> analyze(ProcessedImage image) async {
    throw error;
  }
}
