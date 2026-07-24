// 拍食记当日上下文构造器。从 profile + 今日 meal_entries 投影到 DailyContext。
// CLAUDE.md §5.2：红黄绿灯引擎需要当日已摄入汇总 + 目标 + 过敏。
import 'dart:convert';

import '../domain/traffic_light_engine.dart';
import 'data.dart';

class DailyContextBuilder {
  DailyContextBuilder._();

  /// 构造当日上下文。date 'YYYY-MM-DD'。
  static Future<DailyContext> build(DataScope scope, {DateTime? now}) async {
    final n = now ?? DateTime.now();
    final date = _dateKey(n);
    final profile = await scope.profileDao.get();
    final totals = await scope.mealEntriesDao.dailyTotals(date);

    final targetCalories = profile?.targetCalories ?? 2000;
    final targetProtein = profile?.proteinG.round() ?? 140;
    final goalType = profile?.goalType ?? 1;
    final consumedCal = totals.calories;
    final consumedProtein = totals.protein;

    List<String> allergies = const [];
    if (profile != null && profile.allergies.isNotEmpty) {
      try {
        final d = jsonDecode(profile.allergies);
        if (d is List) {
          allergies = d.map((e) => '$e').toList();
        }
      } catch (_) {
        allergies = const [];
      }
    }

    return DailyContext(
      goalType: goalType,
      targetCalories: targetCalories,
      consumedCalories: consumedCal,
      targetProtein: targetProtein,
      consumedProtein: consumedProtein,
      allergies: allergies,
    );
  }

  static String _dateKey(DateTime n) =>
      '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}
