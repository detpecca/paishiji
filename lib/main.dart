import 'package:flutter/material.dart';

import 'core/theme.dart';

void main() {
  runApp(const PaishijiApp());
}

class PaishijiApp extends StatelessWidget {
  const PaishijiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '拍食记',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const _PlaceholderHome(),
    );
  }
}

// 临时占位首页。Task 2/6 起替换为 onboarding + 首页环形进度。
class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

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
              Text('工程骨架就绪', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Task 0 已完成，待 Task 1 起逐步填充。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
