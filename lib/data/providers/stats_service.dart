// 拍食记统计服务。CLAUDE.md §六 Task 8：
// 设置页显示本月识别次数与估算 API 花费（本地计数，不计费）。
//
// 纯协调：kv 按月存 recognition_count_YYYY-MM。pipeline 每次识别自增。
// now 可注入便于跨月测试。零真实计费，纯本地估算。
import '../../core/constants.dart';
import '../data.dart';

/// 本月识别统计快照。
class RecognitionStats {
  const RecognitionStats({required this.monthKey, required this.count});
  final String monthKey; // YYYY-MM
  final int count;

  /// 估算 API 花费（¥）。CLAUDE.md §二：单次约 ¥0.01~0.05，取中位 0.03。
  double get estimatedCostRmb => count * AppConstants.recognitionCostPerCallRmb;
}

/// 统计服务。注入 DataScope 与可选 [now]。
class StatsService {
  StatsService(this.scope, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DataScope scope;
  final DateTime Function() _now;

  /// 当前月份的识别统计。
  Future<RecognitionStats> currentMonth() async {
    final key = _kvKey(_now());
    final raw = await scope.kvDao.get(key);
    final count = int.tryParse(raw ?? '') ?? 0;
    return RecognitionStats(monthKey: _monthKey(_now()), count: count);
  }

  /// 自增本月识别次数（pipeline 每次识别后调用）。
  Future<void> incrementRecognition() async {
    final key = _kvKey(_now());
    final raw = await scope.kvDao.get(key);
    final count = int.tryParse(raw ?? '') ?? 0;
    await scope.kvDao.set(key, '${count + 1}');
  }

  static String _monthKey(DateTime n) =>
      '${n.year}-${n.month.toString().padLeft(2, '0')}';

  static String _kvKey(DateTime n) =>
      '${AppConstants.recognitionCountKvPrefix}${_monthKey(n)}';
}
