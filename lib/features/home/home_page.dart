// 拍食记首页占位。Task 6 替换为环形进度 + 今日餐次 + 大拍照按钮。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:paishiji/core/router.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('拍食记'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () => context.go(AppRoutes.settings),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.restaurant_menu,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text('已建档，待 Task 6 实现首页', style: theme.textTheme.headlineSmall),
            ],
          ),
        ),
      ),
      // 临时把"去拍照"按钮放在 home，方便真机验证 Task 3 的 key 引导态
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(AppRoutes.capture),
        icon: const Icon(Icons.camera_alt),
        label: const Text('拍一餐'),
      ),
    );
  }
}
