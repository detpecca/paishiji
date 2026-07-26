// 拍食记 seed_loader 端到端单测：用真实 seed_foods.json 资产走完
// ensureSeeded，验证冷启动 ≥300 条、重复不重复导入。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/data/data.dart';

class _StubBundle extends AssetBundle {
  _StubBundle(this.json);
  final Map<String, String> json;
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final v = json[key];
    if (v == null) {
      throw ArgumentError('asset not found: $key');
    }
    return v;
  }

  @override
  Future<ByteData> load(String key) async => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DataScope.ensureSeeded with real asset', () {
    test('冷启动后 foods ≥ 300 条（真实 seed_foods.json）', () async {
      final real = await rootBundle.loadString('assets/seed_foods.json');
      final bundle = _StubBundle({'assets/seed_foods.json': real});

      final db = AppDatabase.forTesting(null);
      final scope = DataScope(db);
      addTearDown(db.close);

      await DataScope.ensureSeeded(
        scope,
        seedJson: await bundle.loadString('assets/seed_foods.json'),
      );
      expect(await scope.foodsDao.all(), hasLength(greaterThanOrEqualTo(300)));
      expect(await scope.kvDao.get(kSeedVersionKey), '$kCurrentSeedVersion');
    });

    test('重复启动不重复导入（同名不会翻倍）', () async {
      final db = AppDatabase.forTesting(null);
      final scope = DataScope(db);
      addTearDown(db.close);

      // 不注入 seedJson，直接走 DataScope.loadSeedJson（rootBundle 在测试环境已注册资产）
      await DataScope.ensureSeeded(scope);
      final countAfterFirst = (await scope.foodsDao.all()).length;
      expect(countAfterFirst, greaterThanOrEqualTo(300));

      await DataScope.ensureSeeded(scope);
      final countAfterSecond = (await scope.foodsDao.all()).length;
      expect(countAfterSecond, countAfterFirst); // 零增长
    });
  });
}
