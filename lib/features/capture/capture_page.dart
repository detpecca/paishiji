// 拍食记拍照页。CLAUDE.md §六 Task 3 DoD：无 key 时显示引导页而非报错。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:paishiji/core/app_services.dart';
import 'package:paishiji/core/router.dart';

class CapturePage extends StatelessWidget {
  const CapturePage({required this.services, super.key});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final hasKey = services.hasDashScopeKey;
    return Scaffold(
      appBar: AppBar(title: const Text('拍食记')),
      body: hasKey ? const _CaptureReady() : const _CaptureMissingKey(),
    );
  }
}

/// 有 key：占位，待 Task 5 实现拍照/相册/裁剪 → 识别。
class _CaptureReady extends StatelessWidget {
  const _CaptureReady();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('点按下方按钮拍摄餐盘', style: theme.textTheme.titleMedium),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {}, // TODO(task-5): 拍照 → 裁剪 → 识别
              icon: const Icon(Icons.photo_camera),
              label: const Text('拍照'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {}, // TODO(task-5): 相册选图
              icon: const Icon(Icons.photo_library),
              label: const Text('从相册选择'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 无 key：引导卡（不报错），带"去设置"按钮。
class _CaptureMissingKey extends StatelessWidget {
  const _CaptureMissingKey();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.key_off, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('尚未配置 API Key', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '拍食记用阿里百炼 Qwen-VL-Max 识别食物，使用前需在设置页填入 DashScope API Key。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go(AppRoutes.settings),
              icon: const Icon(Icons.settings),
              label: const Text('去设置'),
            ),
          ],
        ),
      ),
    );
  }
}
