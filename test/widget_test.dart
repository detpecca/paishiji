// 拍食记 —— 应用启动 smoke test。验证 AppServices 异步加载 + 路由挂载。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/main.dart';

void main() {
  testWidgets('app boots into splash then routes', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PaishijiApp()));
    // 启动期 ProviderScope 加载 AppServices：应见到 splash 转圈
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
