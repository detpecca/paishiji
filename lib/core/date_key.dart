// 拍食记日期工具。CLAUDE.md §六 Task 6：0 点跨天正确滚动。
// 统一 'YYYY-MM-DD' 格式，避免时区/本地化踩坑。
class DateKey {
  DateKey._();

  /// 当日 key（本地时区）。
  static String today([DateTime? now]) {
    final n = now ?? DateTime.now();
    return of(n);
  }

  static String of(DateTime n) =>
      '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';

  /// 从 key 解析回 DateTime（当日起始 00:00）。
  static DateTime parse(String key) {
    final parts = key.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }
}
