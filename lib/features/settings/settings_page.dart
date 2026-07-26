// 拍食记设置页。CLAUDE.md §六 Task 3 + Task 8：
// - DashScope key 必填才能使用识别；GLM 选填
// - 存 flutter_secure_storage（经 KeyVault 抽象）
// - "测试连接"按钮发最小请求验证 key
// - Task 8：导出/导入备份 + 本月识别次数与估算花费
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:paishiji/core/app_exceptions.dart';
import 'package:paishiji/core/app_services.dart';
import 'package:paishiji/core/router.dart';
import 'package:paishiji/data/providers/backup_service.dart';
import 'package:paishiji/data/providers/key_vault.dart';
import 'package:paishiji/data/providers/stats_service.dart';
import 'package:paishiji/features/onboarding/onboarding_flow.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

class SettingsPage extends StatefulWidget {
  const SettingsPage({required this.services, super.key});
  final AppServices services;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _dashCtrl = TextEditingController();
  final _glmCtrl = TextEditingController();
  bool _loading = false;
  String? _dashFeedback;
  String? _glmFeedback;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final dash = await widget.services.keyVault.read(ApiKeyType.dashscope);
    final glm = await widget.services.keyVault.read(ApiKeyType.glm);
    if (mounted) {
      _dashCtrl.text = dash ?? '';
      _glmCtrl.text = glm ?? '';
      setState(() {});
    }
  }

  @override
  void dispose() {
    _dashCtrl.dispose();
    _glmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    await widget.services.keyVault.write(
      ApiKeyType.dashscope,
      _dashCtrl.text.trim().isEmpty ? null : _dashCtrl.text.trim(),
    );
    await widget.services.keyVault.write(
      ApiKeyType.glm,
      _glmCtrl.text.trim().isEmpty ? null : _glmCtrl.text.trim(),
    );
    await widget.services.onKeyChanged();
    if (mounted) {
      setState(() {
        _loading = false;
        _dashFeedback = null;
        _glmFeedback = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已保存')));
    }
  }

  Future<void> _testDash() async {
    final key = _dashCtrl.text.trim();
    if (key.isEmpty) {
      setState(() => _dashFeedback = '请先填入 DashScope Key');
      return;
    }
    setState(() {
      _loading = true;
      _dashFeedback = null;
    });
    final r = await widget.services.tester.testDashScope(key);
    if (mounted) {
      setState(() {
        _loading = false;
        _dashFeedback = r.display;
      });
    }
  }

  Future<void> _testGlm() async {
    final key = _glmCtrl.text.trim();
    setState(() {
      _loading = true;
      _glmFeedback = null;
    });
    final r = await widget.services.tester.testGlm(key);
    if (mounted) {
      setState(() {
        _loading = false;
        _glmFeedback = key.isEmpty ? '请先填入 GLM Key' : r.display;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: AbsorbPointer(
        absorbing: _loading,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _SectionTitle(
              '视觉识别 API',
              trailing: EstimatedBadge(label: '识别额度按量付费'),
            ),
            _KeyCard(
              label: '阿里百炼 DashScope（必填）',
              hint: 'sk-...',
              controller: _dashCtrl,
              feedback: _dashFeedback,
              onTest: _testDash,
              required: true,
            ),
            const SizedBox(height: 12),
            _KeyCard(
              label: '智谱 GLM（选填，备用降级）',
              hint: 'xxx.xxx',
              controller: _glmCtrl,
              feedback: _glmFeedback,
              onTest: _testGlm,
              required: false,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loading ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('保存'),
            ),
            const Divider(height: 32),
            const _SectionTitle('本月识别'),
            _StatsCard(services: widget.services),
            const Divider(height: 32),
            const _SectionTitle('备份与恢复'),
            _BackupCard(services: widget.services),
            const Divider(height: 32),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('关于'),
              subtitle: const Text('拍食记 · 纯手机端个人饮食记录'),
              onTap: () => _showAbout(context),
            ),
            ListTile(
              leading: const Icon(Icons.restaurant_menu),
              title: const Text('重做引导'),
              onTap: () => context.go(AppRoutes.onboarding),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关于拍食记'),
        content: const Text(
          '无服务器、无账号、无云同步。\n'
          '外部依赖：阿里百炼 Qwen-VL-Max（主）、智谱 GLM-4V（备）、Open Food Facts（条码）。\n'
          '所有数据本地存储，可导出/导入备份。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          Text(text, style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class _KeyCard extends StatelessWidget {
  const _KeyCard({
    required this.label,
    required this.hint,
    required this.controller,
    required this.feedback,
    required this.onTest,
    required this.required,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final String? feedback;
  final Future<void> Function() onTest;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label${required ? "" : ""}'),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton(onPressed: onTest, child: const Text('测试连接')),
                const SizedBox(width: 12),
                Expanded(child: _FeedbackText(feedback)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackText extends StatelessWidget {
  const _FeedbackText(this.text);
  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    final isValid = text == '密钥有效';
    return Text(
      text!,
      style: TextStyle(
        color: isValid ? Colors.green : Theme.of(context).colorScheme.error,
        fontSize: 13,
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RecognitionStats>(
      future: StatsService(services.data).currentMonth(),
      builder: (context, snap) {
        final stats = snap.data;
        final count = stats?.count ?? 0;
        final cost = stats?.estimatedCostRmb ?? 0;
        return Card(
          child: ListTile(
            leading: const Icon(Icons.photo_camera),
            title: Text('$count 次'),
            subtitle: Text(
              '${stats?.monthKey ?? ""}  ·  估算花费 ≈¥${cost.toStringAsFixed(2)}',
            ),
            trailing: const EstimatedBadge(label: '本地计数'),
          ),
        );
      },
    );
  }
}

class _BackupCard extends StatefulWidget {
  const _BackupCard({required this.services});
  final AppServices services;

  @override
  State<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<_BackupCard> {
  bool _busy = false;
  String? _feedback;

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final svc = BackupService(widget.services.data);
      final path = await svc.export();
      // share_plus 分享文件
      await Share.shareXFiles([XFile(path)], text: '拍食记备份');
      if (!mounted) return;
      setState(() {
        _feedback = '已导出，请保存到安全位置';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _feedback = '导出失败：${e is AppException ? e.message : '$e'}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (picked == null || picked.files.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final path = picked.files.single.path;
      if (path == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final raw = await File(path).readAsString();
      // 导入是覆盖恢复，先确认。
      final ok = await _confirmImport();
      if (!ok || !mounted) {
        setState(() => _busy = false);
        return;
      }
      final svc = BackupService(widget.services.data);
      await svc.import(raw);
      // 导入后刷新首页（备份时间也更新了，提醒横幅应消失）。
      await widget.services.data.homeView.refresh();
      if (!mounted) return;
      setState(() {
        _feedback = '导入完成';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _feedback = '导入失败：${e is AppException ? e.message : '$e'}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmImport() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入备份'),
        content: const Text('导入会覆盖当前所有数据，确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定导入'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _export,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('导出备份'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _import,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('导入备份'),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (_feedback != null) ...[
              const SizedBox(height: 8),
              Text(_feedback!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
