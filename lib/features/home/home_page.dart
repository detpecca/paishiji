// 拍食记首页占位。Task 6 替换为环形进度 + 今日餐次 + 大拍照按钮。
import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('拍食记')),
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
    );
  }
}
