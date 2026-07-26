// 拍食记首页。CLAUDE.md §六 Task 6：
// 环形进度（热量+三大营养素 vs 目标）+ 今日各餐卡片 + 大拍照按钮。
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart' as fl;
import 'package:go_router/go_router.dart';
import 'package:paishiji/core/app_services.dart';
import 'package:paishiji/core/router.dart';
import 'package:paishiji/features/onboarding/onboarding_flow.dart';

import 'home_view_model.dart';

/// 首页宿主：持有 HomeView，注入 AppServices.data。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late HomeView _view;

  @override
  void initState() {
    super.initState();
    // 注：此处用全局 AppServices.data；测试可 override。
    // 真实 AppServices 由 ProviderScope 注入；此处简化用顶层 provider 引用。
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final svc = AppServicesScope.of(context);
    _view = svc.data.homeView;
    _view.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('拍食记'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: '日记',
            onPressed: () => context.go(AppRoutes.diary),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () => context.go(AppRoutes.settings),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _view,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_view.needsBackupReminder) const _BackupReminderBanner(),
              _ProgressRing(view: _view),
              const SizedBox(height: 16),
              Text('今日各餐', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (_view.todayGroups.isEmpty)
                const _EmptyMeals()
              else
                for (final g in _view.todayGroups) _MealGroupCard(group: g),
            ],
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'scan',
            tooltip: '扫码',
            onPressed: () => context.go(AppRoutes.barcode),
            child: const Icon(Icons.qr_code_scanner),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'capture',
            onPressed: () => context.go(AppRoutes.capture),
            icon: const Icon(Icons.camera_alt),
            label: const Text('拍一餐'),
          ),
        ],
      ),
    );
  }
}

/// 跨树取 AppServices（由 main.dart ProviderScope 注入）。
/// 简化：用 InheritedWidget 风格；真实由 ProviderScope 提供。
class AppServicesScope extends InheritedWidget {
  const AppServicesScope({
    required this.services,
    required super.child,
    super.key,
  });
  final AppServices services;

  static AppServices of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<AppServicesScope>();
    return w!.services;
  }

  @override
  bool updateShouldNotify(AppServicesScope oldWidget) =>
      services != oldWidget.services;
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.view});
  final HomeView view;

  @override
  Widget build(BuildContext context) {
    final target = view.targetCalories;
    final consumed = view.consumedCalories;
    final pct = target > 0 ? (consumed / target).clamp(0.0, 1.0) : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  fl.PieChart(
                    fl.PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 38,
                      sections: [
                        fl.PieChartSectionData(
                          value: pct.toDouble(),
                          color: Theme.of(context).colorScheme.primary,
                          radius: 14,
                          showTitle: false,
                        ),
                        if (1 - pct > 0)
                          fl.PieChartSectionData(
                            value: 1 - pct,
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            radius: 14,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${consumed.round()}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text('kcal', style: TextStyle(fontSize: 11)),
                      const EstimatedBadge(),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MacroBar(
                    label: '蛋白质',
                    consumed: view.consumedProtein,
                    target: view.targetProtein,
                    unit: 'g',
                  ),
                  _MacroBar(
                    label: '碳水',
                    consumed: view.consumedCarbs,
                    target: view.targetCarbs,
                    unit: 'g',
                  ),
                  _MacroBar(
                    label: '脂肪',
                    consumed: view.consumedFat,
                    target: view.targetFat,
                    unit: 'g',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '目标 ${target}kcal',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroBar extends StatelessWidget {
  const _MacroBar({
    required this.label,
    required this.consumed,
    required this.target,
    required this.unit,
  });

  final String label;
  final double consumed;
  final double target;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final pct = target > 0 ? (consumed / target).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 48, child: Text(label)),
          Expanded(
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(
              '${consumed.round()}/${target.round()}$unit',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMeals extends StatelessWidget {
  const _EmptyMeals();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.restaurant_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text('今天还没记录', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('点右下角"拍一餐"开始记录', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _BackupReminderBanner extends StatelessWidget {
  const _BackupReminderBanner();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFF8E1),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.cloud_upload, color: Color(0xFFBF7100)),
        title: const Text('该备份了'),
        subtitle: const Text('距上次备份已超过 7 天，去设置页导出备份以防数据丢失'),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFFBF7100)),
        onTap: () => context.go(AppRoutes.settings),
      ),
    );
  }
}

class _MealGroupCard extends StatelessWidget {
  const _MealGroupCard({required this.group});
  final MealGroup group;

  static const _names = {1: '早餐', 2: '午餐', 3: '晚餐', 4: '加餐'};

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(_names[group.mealType] ?? '餐次${group.mealType}'),
        subtitle: Text('${group.entries.length} 项'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '≈${group.calories.round()}kcal',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 4),
            const EstimatedBadge(),
          ],
        ),
      ),
    );
  }
}
