// 拍食记 onboarding 6 屏向导。PageView 实现，可回退编辑、结果页可手改。
import 'package:flutter/material.dart';

import 'onboarding_controller.dart';
import 'onboarding_pages.dart';
export 'onboarding_pages.dart';

/// 入口：onboarding 流程容器。返回提交后的 OnboardingDraft（供落库）。
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({required this.onFinished, super.key});

  final Future<void> Function(OnboardingDraft draft, DateTime now) onFinished;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  late final OnboardingController _controller;
  late final PageController _pages;
  final _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _controller = OnboardingController();
    _pages = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    _pages.dispose();
    super.dispose();
  }

  static const _titles = ['基本信息', '身高体重', '你的目标', '减脂速率', '活动量', '确认方案'];

  void _next() {
    if (_controller.page < 5) {
      _pages.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
      setState(() => _controller.page++);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_controller.page > 0) {
      _pages.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
      setState(() => _controller.page--);
    }
  }

  Future<void> _submit() async {
    await widget.onFinished(_controller.value, _now);
  }

  @override
  Widget build(BuildContext context) {
    final draft = _controller.value;
    final canNext = switch (_controller.page) {
      0 => draft.step1Valid,
      1 => draft.step2Valid,
      _ => true,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_controller.page]),
        leading: _controller.page == 0
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_controller.page + 1) / 6,
            minHeight: 4,
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                BasicInfoPage(controller: _controller),
                BodyMetricsPage(controller: _controller),
                GoalTypePage(controller: _controller),
                GoalRatePage(controller: _controller),
                ActivityLevelPage(controller: _controller),
                ConfirmResultPage(controller: _controller, now: _now),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: FilledButton(
              onPressed: canNext ? _next : null,
              child: Text(_controller.page == 5 ? '完成，进入拍食记' : '下一步'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 热量估算角标 widget（红线#1：UI 热量数字带"估算"标识）。
class EstimatedBadge extends StatelessWidget {
  const EstimatedBadge({super.key, this.label = '估算'});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
