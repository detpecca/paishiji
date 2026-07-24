// 拍食记拍照页。CLAUDE.md §六 Task 3/5：
// 无 key → 引导页（不报错）；有 key → 拍照/相册 → 裁剪 → 跳识别页。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:paishiji/core/app_services.dart';
import 'package:paishiji/core/router.dart';
import 'package:paishiji/features/capture/capture_service.dart';

class CapturePage extends StatefulWidget {
  const CapturePage({required this.services, super.key});
  final AppServices services;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  bool _picking = false;

  Future<void> _pick(CaptureSource source) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      // 生产用 ImagePickerCaptureService；测试可由 services 注入（Task 5 后续）。
      final svc = ImagePickerCaptureService();
      final result = await svc.pickAndCrop(source);
      if (!mounted) return;
      if (result == null) {
        // 用户取消
        return;
      }
      // 跳识别页：传 imagePath。识别页从 AppServices 取 pipeline 依赖。
      context.go(
        '${AppRoutes.recognition}?path=${Uri.encodeComponent(result.path)}',
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = widget.services.hasDashScopeKey;
    return Scaffold(
      appBar: AppBar(title: const Text('拍食记')),
      body: hasKey
          ? _CaptureReady(onPick: _pick, busy: _picking)
          : const _CaptureMissingKey(),
    );
  }
}

class _CaptureReady extends StatelessWidget {
  const _CaptureReady({required this.onPick, required this.busy});
  final Future<void> Function(CaptureSource) onPick;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AbsorbPointer(
      absorbing: busy,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.camera_alt,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text('点按下方按钮拍摄餐盘', style: theme.textTheme.titleMedium),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: busy ? null : () => onPick(CaptureSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: const Text('拍照'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : () => onPick(CaptureSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('从相册选择'),
              ),
              if (busy) ...const [
                SizedBox(height: 16),
                CircularProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

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
