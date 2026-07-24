// 拍食记识别结果页。CLAUDE.md §六 Task 5：
// loading("正在识别，约3秒") → 结果卡片列表。
// 每卡片：菜名、份量滑块(50g步进)、热量、三大营养素、红黄绿灯徽标、一句话理由；
// 整餐合计条；低置信度(<0.7)黄条警示 + 候选列表点选纠正；
// "不对？纠正"换食物/改份量/文字补充后重识别；
// "存入今日"按餐次归档。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:paishiji/core/app_exceptions.dart';
import 'package:paishiji/core/date_key.dart';
import 'package:paishiji/data/data.dart';
import 'package:paishiji/data/daily_context.dart';
import 'package:paishiji/data/providers/image_processor.dart';
import 'package:paishiji/data/providers/recognition_pipeline.dart';
import 'package:paishiji/data/providers/vision_provider.dart';
import 'package:paishiji/domain/nutrition_matcher.dart';
import 'package:paishiji/features/onboarding/onboarding_flow.dart';

import 'recognition_controller.dart';

// 估算角标复用（红线#1：UI 热量数字带"估算"标识），re-export 供测试导入。
export 'package:paishiji/features/onboarding/onboarding_flow.dart'
    show EstimatedBadge;

/// 识别页入参：裁剪后图片路径 + 已注入的 pipeline 依赖。
class RecognitionPage extends StatefulWidget {
  const RecognitionPage({
    required this.imagePath,
    required this.scope,
    required this.imageProcessor,
    required this.vision,
    super.key,
  });

  final String imagePath;
  final DataScope scope;
  final ImageProcessor imageProcessor;
  final VisionProvider vision;

  @override
  State<RecognitionPage> createState() => _RecognitionPageState();
}

class _RecognitionPageState extends State<RecognitionPage> {
  late final Future<RecognitionDraft> _future;

  @override
  void initState() {
    super.initState();
    _future = _recognize();
  }

  Future<RecognitionDraft> _recognize() async {
    final daily = await DailyContextBuilder.build(widget.scope);
    final pipeline = RecognitionPipeline(
      imageProcessor: widget.imageProcessor,
      vision: widget.vision,
      scope: widget.scope,
      daily: daily,
    );
    final result = await pipeline.run(widget.imagePath);
    final items = <EditableItem>[];
    for (final v in result.items) {
      // 把库内 Food 投影到 FoodRecord（含 sugar：种子库无 sugar 列，暂置 0）
      final food = v.foodId == null
          ? FoodRecord(
              id: -1,
              name: v.detectedName,
              aliasesJson: '[]',
              caloriesPer100g: 0,
              proteinPer100g: 0,
              carbsPer100g: 0,
              fatPer100g: 0,
            )
          : await _loadFood(v.foodId!);
      items.add(
        EditableItem(
          view: v,
          per100g: food,
          daily: daily,
          sugarPer100g: 0, // TODO(task-7): 种子库补 sugar 后接入
        ),
      );
    }
    return RecognitionDraft(items: items);
  }

  Future<FoodRecord> _loadFood(int id) async {
    final f = await widget.scope.foodsDao.findById(id);
    if (f == null) {
      return FoodRecord(
        id: id,
        name: '?',
        aliasesJson: '[]',
        caloriesPer100g: 0,
        proteinPer100g: 0,
        carbsPer100g: 0,
        fatPer100g: 0,
      );
    }
    return FoodRecord(
      id: f.id,
      name: f.name,
      aliasesJson: f.aliases,
      caloriesPer100g: f.caloriesPer100g,
      proteinPer100g: f.proteinPer100g,
      carbsPer100g: f.carbsPer100g,
      fatPer100g: f.fatPer100g,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('识别结果')),
      body: FutureBuilder<RecognitionDraft>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const _Loading();
          }
          if (snap.hasError) {
            return _Error(error: snap.error!);
          }
          final draft = snap.data!;
          return _ResultBody(draft: draft, scope: widget.scope);
        },
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('正在识别，约 3 秒…'),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    final msg = error is AppException
        ? (error as AppException).message
        : '$error';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(msg, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('返回重拍'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultBody extends StatefulWidget {
  const _ResultBody({required this.draft, required this.scope});
  final RecognitionDraft draft;
  final DataScope scope;

  @override
  State<_ResultBody> createState() => _ResultBodyState();
}

class _ResultBodyState extends State<_ResultBody> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: widget.draft,
            builder: (context, _) {
              return ListView(
                children: [
                  for (final it in widget.draft.items) _ItemCard(item: it),
                ],
              );
            },
          ),
        ),
        _TotalBar(draft: widget.draft),
        _MealTypeSelector(draft: widget.draft),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () => _archive(context),
            icon: const Icon(Icons.check),
            label: const Text('存入今日'),
          ),
        ),
      ],
    );
  }

  Future<void> _archive(BuildContext context) async {
    final date = DateKey.today();
    final ctrl = RecognitionController(
      scope: widget.scope,
      draft: widget.draft,
    );
    final r = await ctrl.archiveToday(date);
    // 归档后刷新首页视图（Task 6：记录后即时刷新）
    await widget.scope.homeView.refresh();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已归档 ${r.writtenIds.length} 项')));
    unawaited(Navigator.of(context).maybePop());
  }
}

class _MealTypeSelector extends StatelessWidget {
  const _MealTypeSelector({required this.draft});
  final RecognitionDraft draft;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('早')),
              ButtonSegment(value: 2, label: Text('午')),
              ButtonSegment(value: 3, label: Text('晚')),
              ButtonSegment(value: 4, label: Text('加餐')),
            ],
            selected: {draft.mealType},
            onSelectionChanged: (s) => draft.setMealType(s.first),
          ),
        );
      },
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});
  final EditableItem item;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: item,
      builder: (context, _) {
        final it = item;
        final tlr = it.trafficLight;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      tlr.signal.emoji,
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        it.view.detectedName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      'conf ${it.view.confidence.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                if (it.lowConfidence) _LowConfidenceBar(item: it),
                if (it.unmatched) const _UnmatchedHint(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('份量'),
                    Expanded(
                      child: Slider(
                        value: it.grams.toDouble(),
                        min: 50,
                        max: 800,
                        divisions: 15, // 50g 步进
                        label: '${it.grams}g',
                        onChanged: (v) => it.setGrams(v.round()),
                      ),
                    ),
                    Text('${it.grams}g'),
                  ],
                ),
                _NutritionRow(it: it),
                const SizedBox(height: 4),
                Text(tlr.advice, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LowConfidenceBar extends StatelessWidget {
  const _LowConfidenceBar({required this.item});
  final EditableItem item;

  @override
  Widget build(BuildContext context) {
    final candidates = item.view.candidates;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF9A825)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '识别不确定，点选正确食物纠正：',
            style: TextStyle(color: Color(0xFFBF7100)),
          ),
          if (candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('无候选，点"不对？纠正"手动补充'),
            )
          else
            Wrap(
              spacing: 8,
              children: [
                for (final c in candidates)
                  ActionChip(
                    label: Text(c.name),
                    onPressed: () => item.swapTo(c),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _UnmatchedHint extends StatelessWidget {
  const _UnmatchedHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        '未命中营养库，营养待确认',
        style: TextStyle(color: Color(0xFFC62828)),
      ),
    );
  }
}

class _NutritionRow extends StatelessWidget {
  const _NutritionRow({required this.it});
  final EditableItem it;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Macro('热量', '≈${it.calories.round()}kcal'),
        const EstimatedBadge(),
        _Macro('蛋白', '${it.protein.round()}g'),
        _Macro('碳水', '${it.carbs.round()}g'),
        _Macro('脂肪', '${it.fat.round()}g'),
      ],
    );
  }
}

class _Macro extends StatelessWidget {
  const _Macro(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _TotalBar extends StatelessWidget {
  const _TotalBar({required this.draft});
  final RecognitionDraft draft;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              const Text('整餐合计'),
              const SizedBox(width: 8),
              Text(
                '≈${draft.totalCalories.round()}kcal',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 4),
              const EstimatedBadge(),
              const Spacer(),
              Text(
                'P${draft.totalProtein.round()} C${draft.totalCarbs.round()} F${draft.totalFat.round()}',
              ),
            ],
          ),
        );
      },
    );
  }
}
