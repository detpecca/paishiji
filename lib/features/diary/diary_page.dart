// 拍食记日记页。CLAUDE.md §六 Task 6：
// 日历（达标绿点/超标红点）+ 选日明细 + 左滑删除。
import 'package:flutter/material.dart';
import 'package:paishiji/core/app_services.dart';
import 'package:paishiji/core/date_key.dart';
import 'package:paishiji/data/data.dart';
import 'package:paishiji/features/onboarding/onboarding_flow.dart';

class DiaryPage extends StatefulWidget {
  const DiaryPage({required this.services, super.key});
  final AppServices services;

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  late DateTime _month;
  String? _selectedKey;

  @override
  void initState() {
    super.initState();
    _month = DateTime(DateTime.now().year, DateTime.now().month);
    _selectedKey = DateKey.today();
  }

  Future<Map<String, double>> _loadMonthTotals() async {
    final result = <String, double>{};
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    for (var d = 1; d <= daysInMonth; d++) {
      final key = DateKey.of(DateTime(_month.year, _month.month, d));
      final t = await widget.services.data.mealEntriesDao.dailyTotals(key);
      result[key] = t.calories;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${_month.year}年${_month.month}月'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(
              () => _month = DateTime(_month.year, _month.month - 1),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(
              () => _month = DateTime(_month.year, _month.month + 1),
            ),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, double>>(
        future: _loadMonthTotals(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _Calendar(
            month: _month,
            totals: snap.data!,
            target: widget.services.data.profileDao,
            selectedKey: _selectedKey,
            onSelect: (k) => setState(() => _selectedKey = k),
          );
        },
      ),
      bottomNavigationBar: _selectedKey == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: _SelectedDayPanel(
                  scope: widget.services.data,
                  dateKey: _selectedKey!,
                  onChanged: () => setState(() {}),
                ),
              ),
            ),
    );
  }
}

class _Calendar extends StatelessWidget {
  const _Calendar({
    required this.month,
    required this.totals,
    required this.target,
    required this.selectedKey,
    required this.onSelect,
  });

  final DateTime month;
  final Map<String, double> totals;
  final ProfileDao target;
  final String? selectedKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: target.get(),
      builder: (context, snap) {
        final targetCal = snap.data?.targetCalories ?? 2000;
        final firstWeekday = DateTime(
          month.year,
          month.month,
          1,
        ).weekday; // 1=Mon
        final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
        // 周一开头：将 weekday(1..7 Mon..Sun) 映射到列 0..6
        final leadingBlanks = (firstWeekday - 1 + 7) % 7;
        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1,
          ),
          itemCount: leadingBlanks + daysInMonth,
          itemBuilder: (context, i) {
            if (i < leadingBlanks) return const SizedBox.shrink();
            final day = i - leadingBlanks + 1;
            final date = DateTime(month.year, month.month, day);
            final key = DateKey.of(date);
            final cal = totals[key] ?? 0;
            final hasData = cal > 0;
            final isOver = hasData && cal > targetCal;
            final isSelected = key == selectedKey;
            return GestureDetector(
              onTap: () => onSelect(key),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                  ),
                ),
                alignment: Alignment.center,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text('$day'),
                    if (hasData)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOver
                                ? const Color(0xFFC62828)
                                : const Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SelectedDayPanel extends StatefulWidget {
  const _SelectedDayPanel({
    required this.scope,
    required this.dateKey,
    required this.onChanged,
  });

  final DataScope scope;
  final String dateKey;
  final VoidCallback onChanged;

  @override
  State<_SelectedDayPanel> createState() => _SelectedDayPanelState();
}

class _SelectedDayPanelState extends State<_SelectedDayPanel> {
  late Future<List<MealEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.scope.mealEntriesDao.ofDate(widget.dateKey);
  }

  @override
  void didUpdateWidget(_SelectedDayPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dateKey != widget.dateKey) {
      _future = widget.scope.mealEntriesDao.ofDate(widget.dateKey);
    }
  }

  void _reload() {
    setState(() {
      _future = widget.scope.mealEntriesDao.ofDate(widget.dateKey);
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Column(
        children: [
          Text(
            '明细 ${widget.dateKey}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Expanded(
            child: FutureBuilder<List<MealEntry>>(
              future: _future,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final entries = snap.data!;
                if (entries.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.event_busy,
                          size: 40,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 8),
                        const Text('当日无记录'),
                      ],
                    ),
                  );
                }
                return ListView(
                  children: [
                    for (final e in entries)
                      Dismissible(
                        key: ValueKey(e.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: const Color(0xFFC62828),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) async {
                          await widget.scope.mealEntriesDao.remove(e.id);
                          _reload();
                        },
                        child: ListTile(
                          title: Text('餐次${e.mealType} · ${e.grams}g'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('≈${e.calories.round()}kcal'),
                              const SizedBox(width: 4),
                              const EstimatedBadge(),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
