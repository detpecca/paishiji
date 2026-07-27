// 拍食记条码扫描页。CLAUDE.md §六 Task 7：
// mobile_scanner 扫码 → OpenFoodFactsClient → 命中展示营养+红绿灯+克重滑块+存入今日；
// 未命中引导拍营养表 → NutritionLabelProvider 解析 → 入库 source=3 → 回到命中展示。
//
// 无 key 时扫码页可用（条码查询走 Open Food Facts 免密钥；营养表补录用 Mock 不阻塞）。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as ms;
import 'package:paishiji/core/app_services.dart';
import 'package:paishiji/data/data.dart';
import 'package:paishiji/data/daily_context.dart';
import 'package:paishiji/data/providers/barcode_flow.dart';
import 'package:paishiji/data/providers/image_processor.dart';
import 'package:paishiji/data/providers/nutrition_label_provider.dart';
import 'package:paishiji/data/providers/open_food_facts.dart';
import 'package:paishiji/domain/traffic_light_engine.dart';
import 'package:paishiji/features/capture/capture_service.dart';
import 'package:paishiji/features/onboarding/onboarding_flow.dart';

/// 扫码页入参：注入 BarcodeFlow 依赖（测试可换 Mock）。
class BarcodePage extends StatefulWidget {
  const BarcodePage({
    required this.services,
    this.openFoodFacts,
    this.labelProvider,
    this.imageProcessor,
    super.key,
  });

  final AppServices services;
  final OpenFoodFactsClient? openFoodFacts;
  final NutritionLabelProvider? labelProvider;
  final ImageProcessor? imageProcessor;

  @override
  State<BarcodePage> createState() => _BarcodePageState();
}

class _BarcodePageState extends State<BarcodePage> {
  late final BarcodeFlow _flow;
  bool _scanning = true;
  _LookupState _state = const _LookupIdle();

  @override
  void initState() {
    super.initState();
    _flow = BarcodeFlow(
      openFoodFacts: widget.openFoodFacts ?? const MockOpenFoodFactsClient(),
      // 真实 label provider（自定义优先→DashScope→GLM）；无 key 时回退 Mock 不阻塞。
      labelProvider:
          widget.labelProvider ??
          widget.services.cachedLabel ??
          const MockLabelProvider(),
      imageProcessor: widget.imageProcessor ?? const DartImageProcessor(),
      scope: widget.services.data,
    );
  }

  Future<void> _onDetect(ms.BarcodeCapture cap) async {
    if (!_scanning) return;
    final codes = cap.barcodes;
    if (codes.isEmpty) return;
    final raw = codes.first.rawValue;
    if (raw == null || raw.isEmpty) return;
    _scanning = false;
    setState(() => _state = _LookupLoading(barcode: raw));
    try {
      final daily = await DailyContextBuilder.build(widget.services.data);
      final result = await _flow.lookup(raw);
      if (result == null) {
        // 未命中：进入"拍营养表补录"引导。
        setState(() => _state = _LookupNotFound(barcode: raw, daily: daily));
      } else {
        setState(() => _state = _LookupFound(result: result, daily: daily));
      }
    } catch (e) {
      setState(() => _state = _LookupError(error: barcodeErrorMessage(e)));
    } finally {
      _scanning = true;
    }
  }

  void _resume() {
    setState(() {
      _state = const _LookupIdle();
      _scanning = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫一扫')),
      body: switch (_state) {
        _LookupIdle() => _ScannerView(onDetect: _onDetect),
        _LookupLoading(:final barcode) => _LoadingView(barcode: barcode),
        _LookupError(:final error) => _ErrorView(
          error: error,
          onRetry: _resume,
        ),
        _LookupNotFound(:final barcode, :final daily) => _NotFoundView(
          barcode: barcode,
          daily: daily,
          flow: _flow,
          onSupplemented: (result) {
            setState(() => _state = _LookupFound(result: result, daily: daily));
          },
          onCancel: _resume,
        ),
        _LookupFound(:final result, :final daily) => _FoundView(
          result: result,
          daily: daily,
          scope: widget.services.data,
          onDone: () => context.go('/'),
          onScanAgain: _resume,
        ),
      },
    );
  }
}

/// 扫码状态机（sealed 让 switch 穷尽）。
sealed class _LookupState {
  const _LookupState();
}

class _LookupIdle extends _LookupState {
  const _LookupIdle();
}

class _LookupLoading extends _LookupState {
  const _LookupLoading({required this.barcode});
  final String barcode;
}

class _LookupError extends _LookupState {
  const _LookupError({required this.error});
  final String error;
}

class _LookupNotFound extends _LookupState {
  const _LookupNotFound({required this.barcode, required this.daily});
  final String barcode;
  final DailyContext daily;
}

class _LookupFound extends _LookupState {
  const _LookupFound({required this.result, required this.daily});
  final BarcodeFlowResult result;
  final DailyContext daily;
}

class _ScannerView extends StatelessWidget {
  const _ScannerView({required this.onDetect});
  final void Function(ms.BarcodeCapture) onDetect;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ms.MobileScanner(onDetect: onDetect),
        Center(
          child: Container(
            width: 260,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        Positioned(
          bottom: 48,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: const Text(
                '将条形码对准框内',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.barcode});
  final String barcode;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('查询条码 $barcode …'),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _NotFoundView extends StatefulWidget {
  const _NotFoundView({
    required this.barcode,
    required this.daily,
    required this.flow,
    required this.onSupplemented,
    required this.onCancel,
  });

  final String barcode;
  final DailyContext daily;
  final BarcodeFlow flow;
  final void Function(BarcodeFlowResult) onSupplemented;
  final VoidCallback onCancel;

  @override
  State<_NotFoundView> createState() => _NotFoundViewState();
}

class _NotFoundViewState extends State<_NotFoundView> {
  bool _supplementing = false;
  String? _error;

  Future<void> _pickAndSupplement() async {
    setState(() {
      _supplementing = true;
      _error = null;
    });
    try {
      final svc = ImagePickerCaptureService();
      final res = await svc.pickAndCrop(CaptureSource.camera);
      if (!mounted) return;
      if (res == null) {
        setState(() => _supplementing = false);
        return;
      }
      final result = await widget.flow.supplementFromLabel(
        barcode: widget.barcode,
        imagePath: res.path,
      );
      if (!mounted) return;
      widget.onSupplemented(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = barcodeErrorMessage(e);
        _supplementing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_2, size: 48),
            const SizedBox(height: 12),
            const Text('未找到该商品'),
            const SizedBox(height: 8),
            const Text(
              '拍一张包装上的"营养成分表"，拍食记会解析后入库。',
              textAlign: TextAlign.center,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _supplementing ? null : _pickAndSupplement,
              icon: const Icon(Icons.photo_camera),
              label: const Text('拍营养表补录'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: widget.onCancel,
              child: const Text('重新扫码'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoundView extends StatefulWidget {
  const _FoundView({
    required this.result,
    required this.daily,
    required this.scope,
    required this.onDone,
    required this.onScanAgain,
  });

  final BarcodeFlowResult result;
  final DailyContext daily;
  final DataScope scope;
  final VoidCallback onDone;
  final VoidCallback onScanAgain;

  @override
  State<_FoundView> createState() => _FoundViewState();
}

class _FoundViewState extends State<_FoundView> {
  static const _step = 50;
  static const _defaultGrams = 100;
  late int _grams = _defaultGrams;
  int _mealType = 2;
  bool _saving = false;

  int _clampGrams(int v) {
    final stepped = (v ~/ _step) * _step;
    return stepped < _step ? _step : stepped;
  }

  TrafficLightResult get _tlr => evaluateBarcodeTrafficLight(
    food: widget.result.foodRecord,
    grams: _grams,
    daily: widget.daily,
  );

  double get _cal => widget.result.foodRecord.caloriesPer100g * _grams / 100;
  double get _pro => widget.result.foodRecord.proteinPer100g * _grams / 100;
  double get _car => widget.result.foodRecord.carbsPer100g * _grams / 100;
  double get _fat => widget.result.foodRecord.fatPer100g * _grams / 100;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await archiveBarcodeEntry(
        scope: widget.scope,
        foodId: widget.result.foodRecord.id,
        grams: _grams,
        mealType: _mealType,
        calories: _cal,
        protein: _pro,
        carbs: _car,
        fat: _fat,
      );
      // 归档后刷新首页视图（Task 6：记录后即时刷新）
      await widget.scope.homeView.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已存入今日')));
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：${barcodeErrorMessage(e)}')));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fr = widget.result.foodRecord;
    final tlr = _tlr;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
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
                        fr.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '条码 ${widget.result.barcode}'
                  '${widget.result.fromCache ? "（本地库）" : "（Open Food Facts）"}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('份量'),
                    Expanded(
                      child: Slider(
                        value: _grams.toDouble(),
                        min: 50,
                        max: 800,
                        divisions: 15, // 50g 步进
                        label: '${_grams}g',
                        onChanged: (v) =>
                            setState(() => _grams = _clampGrams(v.round())),
                      ),
                    ),
                    Text('${_grams}g'),
                  ],
                ),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Macro('热量', '≈${_cal.round()}kcal'),
                    const EstimatedBadge(),
                    _Macro('蛋白', '${_pro.round()}g'),
                    _Macro('碳水', '${_car.round()}g'),
                    _Macro('脂肪', '${_fat.round()}g'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(tlr.advice, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('早')),
            ButtonSegment(value: 2, label: Text('午')),
            ButtonSegment(value: 3, label: Text('晚')),
            ButtonSegment(value: 4, label: Text('加餐')),
          ],
          selected: {_mealType},
          onSelectionChanged: (s) => setState(() => _mealType = s.first),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check),
          label: const Text('存入今日'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _saving ? null : widget.onScanAgain,
          child: const Text('再扫一个'),
        ),
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
