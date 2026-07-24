// 拍食记营养库匹配。CLAUDE.md §5.4：
// detected_name → foods.name 精确 → aliases 匹配 → 模糊(相似度≥0.6) → 未命中(返回 null，调大模型估算 source=2 verified=0)
//
// 纯函数，不依赖 Flutter。aliases 是 JSON 数组字符串（库内存储格式）。
import 'dart:convert';

/// 营养库食物的内存视图（从 Food 行投影）。避免 domain 直接依赖 Drift。
class FoodRecord {
  const FoodRecord({
    required this.id,
    required this.name,
    required this.aliasesJson,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
  });

  final int id;
  final String name;
  final String aliasesJson;
  final double caloriesPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;

  List<String> get aliases {
    try {
      final d = jsonDecode(aliasesJson);
      if (d is List) return d.map((e) => '$e').toList();
    } catch (_) {}
    return const [];
  }
}

/// 匹配结果。
class MatchResult {
  const MatchResult.found(this.record) : candidates = const [];
  const MatchResult.notFound(this.candidates) : record = null;

  final FoodRecord? record;
  final List<FoodRecord> candidates; // 模糊命中的候选（供"不对？纠正"用）

  bool get isFound => record != null;
}

/// 营养库匹配器。纯函数，可单测。
class NutritionMatcher {
  NutritionMatcher._();

  /// 按 detected_name 逐级匹配。
  /// 模糊匹配用 Levenshtein 相似度，≥ [minSimilarity] 视为命中。
  static MatchResult match({
    required String detectedName,
    required List<FoodRecord> foods,
    double minSimilarity = 0.6,
  }) {
    final name = detectedName.trim();
    if (name.isEmpty) return const MatchResult.notFound([]);

    // R1: 精确匹配 name（忽略大小写、去空白）
    for (final f in foods) {
      if (_normalize(f.name) == _normalize(name)) return MatchResult.found(f);
    }
    // R2: aliases 精确匹配
    for (final f in foods) {
      for (final a in f.aliases) {
        if (_normalize(a) == _normalize(name)) return MatchResult.found(f);
      }
    }
    // R3: 模糊匹配 ≥ 阈值，取最高分
    var bestScore = 0.0;
    FoodRecord? best;
    final candidates = <FoodRecord>[];
    for (final f in foods) {
      final score = _bestSimilarity(name, [f.name, ...f.aliases]);
      if (score >= minSimilarity) {
        candidates.add(f);
        if (score > bestScore) {
          bestScore = score;
          best = f;
        }
      }
    }
    if (best != null) return MatchResult.found(best);
    // R4: 未命中。返回候选（即便低于阈值的 top-k 也可供 UI 纠正）
    return MatchResult.notFound(candidates);
  }

  static String _normalize(String s) =>
      s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  static double _bestSimilarity(String a, List<String> pool) {
    var max = 0.0;
    for (final p in pool) {
      final s = _similarity(a, p);
      if (s > max) max = s;
    }
    return max;
  }

  /// 相似度：1 - editDistance / max(len)。简单 Levenshtein。
  static double _similarity(String a, String b) {
    final na = _normalize(a);
    final nb = _normalize(b);
    if (na.isEmpty && nb.isEmpty) return 1.0;
    if (na.isEmpty || nb.isEmpty) return 0.0;
    final dist = _levenshtein(na, nb);
    return 1.0 - dist / (na.length > nb.length ? na.length : nb.length);
  }

  static int _levenshtein(String a, String b) {
    final m = a.length, n = b.length;
    if (m == 0) return n;
    if (n == 0) return m;
    final prev = List<int>.filled(n + 1, 0);
    final curr = List<int>.filled(n + 1, 0);
    for (var j = 0; j <= n; j++) {
      prev[j] = j;
    }
    for (var i = 1; i <= m; i++) {
      curr[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        curr[j] = _min3(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
      }
      for (var j = 0; j <= n; j++) {
        prev[j] = curr[j];
      }
    }
    return prev[n];
  }

  static int _min3(int a, int b, int c) =>
      a < b ? (a < c ? a : c) : (b < c ? b : c);
}
