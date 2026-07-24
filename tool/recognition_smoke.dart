// 拍食记识别 smoke 入口。CLAUDE.md §六 Task 4 DoD。
//
// 因 Windows 下 dart run 对 sqlite3 FFI 有编译 bug，smoke 以 flutter test 形式跑：
//   flutter test test/smoke/recognition_smoke_test.dart
//
// Mock 模式（默认，零真实 API、零图片）：
//   flutter test test/smoke/recognition_smoke_test.dart
//
// Real 模式（真实 key + test/fixtures/ 下 10 张中餐照片）：
//   PAISHIJI_SMOKE_REAL=1 DASHSCOPE_API_KEY=sk-xxx flutter test test/smoke/recognition_smoke_test.dart
//
// 该脚本文件仅作为文档/门面；实际逻辑在 test/smoke/recognition_smoke_test.dart。
library;

// ignore_for_file: avoid_print
Future<void> main(List<String> args) async {
  print('请改用: flutter test test/smoke/recognition_smoke_test.dart');
  print('参数: ${args.isEmpty ? "(Mock 默认)" : args.join(" ")}');
}
