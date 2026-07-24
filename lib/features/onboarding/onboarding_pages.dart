// 拍食记 onboarding 6 个分屏。仅 UI，状态读写都走 OnboardingController。
import 'package:flutter/material.dart';
import 'package:paishiji/domain/tdee_calculator.dart';

import 'onboarding_controller.dart';
import 'onboarding_flow.dart';

class BasicInfoPage extends StatelessWidget {
  const BasicInfoPage({required this.controller, super.key});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final draft = controller.value;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('性别', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SegmentedButton<Gender>(
          segments: const [
            ButtonSegment(value: Gender.male, label: Text('男')),
            ButtonSegment(value: Gender.female, label: Text('女')),
          ],
          selected: {draft.gender ?? Gender.male},
          onSelectionChanged: (s) => controller.setGender(s.first),
        ),
        const SizedBox(height: 24),
        const Text('出生年份', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '例如 2001',
                  border: OutlineInputBorder(),
                ),
                onChanged: (s) {
                  final v = int.tryParse(s);
                  if (v != null) controller.setBirthYear(v);
                },
              ),
            ),
            const SizedBox(width: 12),
            Text(_ageLabel(draft.birthYear)),
          ],
        ),
      ],
    );
  }

  String _ageLabel(int? birthYear) {
    if (birthYear == null) return '';
    final age = DateTime.now().year - birthYear;
    return age > 0 ? '$age 岁' : '';
  }
}

class BodyMetricsPage extends StatelessWidget {
  const BodyMetricsPage({required this.controller, super.key});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final draft = controller.value;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _SliderTile(
            label: '身高',
            value: draft.heightCm,
            min: 120,
            max: 220,
            unit: 'cm',
            onChanged: controller.setHeightCm,
          ),
          _SliderTile(
            label: '体重',
            value: draft.weightKg,
            min: 30,
            max: 150,
            unit: 'kg',
            onChanged: controller.setWeightKg,
          ),
        ],
      ),
    );
  }
}

class GoalTypePage extends StatelessWidget {
  const GoalTypePage({required this.controller, super.key});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final draft = controller.value;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: GoalType.values
          .map(
            (g) => RadioListTile<GoalType>(
              value: g,
              groupValue: draft.goalType,
              onChanged: (v) => v == null ? null : controller.setGoalType(v),
              title: Text(_goalLabel(g)),
            ),
          )
          .toList(),
    );
  }

  String _goalLabel(GoalType g) => switch (g) {
    GoalType.cut => '减脂（1减脂）',
    GoalType.maintain => '维持（2维持）',
    GoalType.gain => '增肌（3增肌）',
  };
}

class GoalRatePage extends StatelessWidget {
  const GoalRatePage({required this.controller, super.key});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final draft = controller.value;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: GoalRate.values
          .map(
            (r) => RadioListTile<GoalRate>(
              value: r,
              groupValue: draft.goalRate,
              onChanged: (v) => v == null ? null : controller.setGoalRate(v),
              title: Text(_rateLabel(r)),
            ),
          )
          .toList(),
    );
  }

  String _rateLabel(GoalRate r) => switch (r) {
    GoalRate.slow => '温和 0.25 kg/周',
    GoalRate.medium => '标准 0.5 kg/周',
    GoalRate.fast => '激进 0.75 kg/周',
  };
}

class ActivityLevelPage extends StatelessWidget {
  const ActivityLevelPage({required this.controller, super.key});
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final draft = controller.value;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: ActivityLevel.values
          .map(
            (a) => RadioListTile<ActivityLevel>(
              value: a,
              groupValue: draft.activityLevel,
              onChanged: (v) =>
                  v == null ? null : controller.setActivityLevel(v),
              title: Text(_activityLabel(a)),
            ),
          )
          .toList(),
    );
  }

  String _activityLabel(ActivityLevel a) => switch (a) {
    ActivityLevel.sedentary => '1 久坐（活动系数 1.2）',
    ActivityLevel.light => '2 轻活动（1.375）',
    ActivityLevel.moderate => '3 中等活动（1.55）',
    ActivityLevel.active => '4 重活动（1.725）',
    ActivityLevel.veryActive => '5 重体力（1.9）',
  };
}

/// 结果确认页：展示 TDEE 计算结果，可手改四项（触发"不再自动覆盖"）。
class ConfirmResultPage extends StatelessWidget {
  const ConfirmResultPage({
    required this.controller,
    required this.now,
    super.key,
  });
  final OnboardingController controller;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OnboardingDraft>(
      valueListenable: controller,
      builder: (context, draft, _) {
        if (!draft.canFinish) {
          return const Center(child: Text('请先完成前几步'));
        }
        final result = draft.resolveTargets(now);
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const EstimatedBadge(label: '以下均为估算'),
            const SizedBox(height: 12),
            _ResultRow(
              label: '每日目标热量',
              value: '${result.targetCalories} kcal',
              editable: true,
              current: draft.targetCalories ?? result.targetCalories,
              onEdited: controller.overrideTargetCalories,
              isKcal: true,
            ),
            _ResultRow(
              label: '蛋白质',
              value: '${result.proteinG.toStringAsFixed(0)} g',
              editable: true,
              currentDouble: draft.proteinG ?? result.proteinG,
              onEditedDouble: controller.overrideProtein,
            ),
            _ResultRow(
              label: '碳水',
              value: '${result.carbsG.toStringAsFixed(0)} g',
              editable: true,
              currentDouble: draft.carbsG ?? result.carbsG,
              onEditedDouble: controller.overrideCarbs,
            ),
            _ResultRow(
              label: '脂肪',
              value: '${result.fatG.toStringAsFixed(0)} g',
              editable: true,
              currentDouble: draft.fatG ?? result.fatG,
              onEditedDouble: controller.overrideFat,
            ),
            const SizedBox(height: 12),
            Text(
              'BMR ${result.bmr.toStringAsFixed(0)} · 维持热量 ${result.tdee.toStringAsFixed(0)} kcal',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            const Text('过敏 / 禁忌食材（可选，识别后会据此标红）'),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: '用逗号分隔，例如 花生, 海鲜',
                border: OutlineInputBorder(),
              ),
              onChanged: (s) => controller.setAllergies(
                s
                    .split(RegExp(r'[,，]'))
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.label,
    required this.value,
    required this.editable,
    this.current,
    this.currentDouble,
    this.onEdited,
    this.onEditedDouble,
    this.isKcal = false,
  });

  final String label;
  final String value;
  final bool editable;
  final int? current;
  final double? currentDouble;
  final ValueChanged<int>? onEdited;
  final ValueChanged<double>? onEditedDouble;
  final bool isKcal;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Row(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (isKcal) ...const [SizedBox(width: 6), EstimatedBadge()],
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.edit),
        onPressed: editable ? () => _showEdit(context) : null,
      ),
    );
  }

  void _showEdit(BuildContext context) {
    final ctrl = TextEditingController(
      text: isKcal
          ? '${current ?? ''}'
          : (currentDouble?.toStringAsFixed(0) ?? ''),
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('手改 $label'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final raw = ctrl.text.trim();
              if (isKcal) {
                final v = int.tryParse(raw);
                if (v != null) onEdited?.call(v);
              } else {
                final v = double.tryParse(raw);
                if (v != null) onEditedDouble?.call(v);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label：${value.toStringAsFixed(0)} $unit',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) / 1).round(),
          label: value.toStringAsFixed(0),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
