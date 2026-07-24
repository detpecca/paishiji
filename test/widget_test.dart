// 拍食记 —— 应用启动 smoke test。验证占位首页可挂载。
import 'package:flutter_test/flutter_test.dart';

import 'package:paishiji/main.dart';

void main() {
  testWidgets('app boots and shows placeholder title', (tester) async {
    await tester.pumpWidget(const PaishijiApp());
    expect(find.text('拍食记'), findsOneWidget);
    expect(find.text('工程骨架就绪'), findsOneWidget);
  });
}
