// 拍食记 — 全局常量。阈值集中在常量类，设置页可改。
// 详见 CLAUDE.md §5.2 / §5.3。
class AppConstants {
  AppConstants._();

  // ── 网络 ──────────────────────────────────────────────
  /// dio 超时。
  static const Duration networkTimeout = Duration(seconds: 20);

  /// dio 最大重试次数（指数退避）。
  static const int networkMaxRetries = 2;

  // ── 图片预处理（CLAUDE.md §5.1）────────────────────────
  static const int imageMaxLongEdge = 1024;
  static const int imageJpegQuality = 80;
  static const int imageMaxBase64Bytes = 300 * 1024; // 300KB

  // ── 红黄绿灯阈值（CLAUDE.md §5.2，可被设置覆盖）─────
  static const double redHighSugarPer100g = 20.0;
  static const double redHighFatPer100g = 20.0;
  static const double greenHighProteinPer100g = 15.0;
  static const double greenLowFatPer100g = 10.0;
  static const double greenBudgetPctThreshold = 0.30;
  static const double lowConfidenceThreshold = 0.70;
  static const double fuzzyMatchMinSimilarity = 0.60;
  static const int visionMaxItems = 8;
  static const double visionTemperature = 0.1;

  // ── TDEE（CLAUDE.md §5.3）─────────────────────────────
  static const List<double> activityFactors = [1.2, 1.375, 1.55, 1.725, 1.9];
  static const List<int> deficitKcalPerWeekRate = [275, 550, 825];
  static const int surplusKcalForGain = 300;
  static const double proteinPerKgCut = 2.0;
  static const double proteinPerKgOther = 1.8;
  static const double fatShareOfCalories = 0.25;

  // ── 备份提醒（CLAUDE.md §5.6）─────────────────────────
  static const Duration backupReminderInterval = Duration(days: 7);

  // ── 模型端点 ──────────────────────────────────────────
  static const String qwenEndpoint =
      'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions';
  static const String glmEndpoint =
      'https://open.bigmodel.cn/api/paas/v4/chat/completions';
  static const String openFoodFactsEndpoint =
      'https://world.openfoodfacts.org/api/v2/product';
}
