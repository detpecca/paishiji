// 拍食记首页状态。CLAUDE.md §六 Task 6：
// - 首页环形进度（热量+三大营养素 vs 目标）+ 今日各餐卡片 + 大拍照按钮
// - 记录后即时刷新
// - 当日汇总与明细求和误差 <1kcal
// - 0 点跨天正确滚动（按 DateTime.now() 实时取今日）
import 'package:flutter/foundation.dart';

import '../../data/data.dart';
import '../../core/date_key.dart';

/// 今日餐次分组（1早 2午 3晚 4加餐）。
class MealGroup {
  const MealGroup({required this.mealType, required this.entries});
  final int mealType;
  final List<MealEntry> entries;

  double get calories => entries.fold(0, (s, e) => s + e.calories);
}

/// 首页视图状态。
class HomeView extends ChangeNotifier {
  HomeView(this._scope);

  final DataScope _scope;

  Profile? _profile;
  List<MealEntry> _todayEntries = const [];
  DateTime _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  Profile? get profile => _profile;
  List<MealEntry> get todayEntries => _todayEntries;
  String get todayKey => DateKey.today();

  int get targetCalories => _profile?.targetCalories ?? 0;
  double get targetProtein => _profile?.proteinG ?? 0;
  double get targetCarbs => _profile?.carbsG ?? 0;
  double get targetFat => _profile?.fatG ?? 0;

  /// 当日汇总（来自 DAO，与明细求和应一致，误差 <1kcal）。
  double get consumedCalories {
    if (_todayEntries.isEmpty) return 0;
    return _todayEntries.fold(0.0, (s, e) => s + e.calories);
  }

  double get consumedProtein =>
      _todayEntries.fold(0.0, (s, e) => s + e.proteinG);
  double get consumedCarbs => _todayEntries.fold(0.0, (s, e) => s + e.carbsG);
  double get consumedFat => _todayEntries.fold(0.0, (s, e) => s + e.fatG);

  /// 按餐次分组的今日明细。
  List<MealGroup> get todayGroups {
    final groups = <int, MealGroup>{};
    for (final e in _todayEntries) {
      final g = groups.putIfAbsent(
        e.mealType,
        () => MealGroup(mealType: e.mealType, entries: []),
      );
      g.entries.add(e);
    }
    // 固定顺序：早午晚加餐
    const order = [1, 2, 3, 4];
    return [
      for (final mt in order)
        if (groups[mt] != null) groups[mt]!,
    ];
  }

  /// 刷新：重读 profile + 今日明细。
  /// [now] 注入便于跨天测试。
  Future<void> refresh({DateTime? now}) async {
    final n = now ?? DateTime.now();
    _profile = await _scope.profileDao.get();
    _todayEntries = await _scope.mealEntriesDao.ofDate(DateKey.today(n));
    _lastRefresh = n;
    notifyListeners();
  }

  /// 校验：明细求和 vs DAO 汇总误差 <1kcal（DoD 自验辅助）。
  Future<double> daoTotalCalories() async {
    final t = await _scope.mealEntriesDao.dailyTotals(
      DateKey.today(_lastRefresh),
    );
    return t.calories;
  }

  /// 校验：明细求和。
  double get entriesSumCalories =>
      _todayEntries.fold(0.0, (s, e) => s + e.calories);
}
