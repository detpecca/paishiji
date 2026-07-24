// 拍食记 seed 加载与差量导入逻辑。
// 实现见同目录 seed_food_parser.dart（纯函数解析）与 lib/data/data.dart
// 的 DataScope.ensureSeeded（首次导入 + kv 标志跳过）。
// 拆成两个文件是为了让解析逻辑可 100% 离线单测，不依赖 Flutter rootBundle。
export '../data.dart';
export 'seed_food_parser.dart';
