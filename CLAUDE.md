# 「拍食记」技术实施文档 —— Claude Code 执行手册

> **给执行者（Claude Code）的指令**：
> 1. 严格按第六章任务顺序执行，每个 Task 的验收标准（DoD）全部自验通过后才能进入下一 Task，不得跨 Task 跳跃。
> 2. 遇到本文档未覆盖的决策，优先选择"更简单、可替换"的方案，并在代码中以 `TODO(decision)` 标注。
> 3. 所有需要真实 API Key 的功能，必须同时提供不耗费的 Mock 实现，保证测试可离线运行。

# 一、项目概述

一款纯手机端的个人自用饮食记录 APP（Android 优先，Flutter 单代码库）。用户拍摄餐盘照片，APP 调用付费视觉大模型 API 识别食物成分、估算热量与宏量营养素，并结合用户减脂/增肌目标给出"🟢推荐吃 / 🟡适量吃 / 🔴不建议吃"结论。

**核心架构原则：无服务器、无账号、无云同步。** 一切逻辑和数据都在端上；外部依赖仅三个 HTTP 服务：阿里 DashScope（主视觉模型）、智谱（备用视觉模型）、Open Food Facts（条形码数据，免费免密钥）。图片以 base64 内嵌方式直传大模型，不需要对象存储。

# 二、技术选型（已锁定，不得擅自更换）

| 层 | 选型 | 说明 |
|---|---|---|
| 框架 | Flutter 3.x（Dart） | Android 优先出 APK，iOS 开发者签名自装 |
| 状态管理 | Riverpod 2.x | — |
| 路由 | go_router | — |
| 本地数据库 | Drift（SQLite） | 类型安全，编译期校验查询 |
| 网络 | dio | 自封装超时(20s)与重试(最多2次、指数退避) |
| 数据类 | freezed + json_serializable | — |
| 视觉模型（主） | 阿里百炼 **Qwen-VL-Max**，OpenAI 兼容端点 `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions`，图片用 `data:image/jpeg;base64,...` 内嵌 | 单次调用约 ¥0.01~0.05 |
| 视觉模型（备） | 智谱 **GLM-4V**，端点 `https://open.bigmodel.cn/api/paas/v4/chat/completions` | 用户在设置页填了第二个 key 才启用 |
| 条形码数据 | Open Food Facts `GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json` | 免费免密钥 |
| 扫码 | mobile_scanner | — |
| 图表 | fl_chart | — |
| 密钥存储 | flutter_secure_storage | API Key 禁止明文进 SharedPreferences |
| 拍照/裁剪 | image_picker + image_cropper | — |
| 备份 | share_plus + file_picker（导出/导入 JSON） | — |

**红线（违反即返工）**
1. 所有热量数字在 UI 上必须带"估算"标识。
2. 大模型调用必须走 Provider 抽象，有超时、降级链、Mock 实现。
3. 不引入任何需要服务器/账号/云同步的功能。
4. 本地数据表均含 created_at 字段。

# 三、仓库结构

```
paishiji/
├── CLAUDE.md                 # 本文档
├── assets/
│   ├── seed_foods.json       # 种子营养库（最终 ≥300 条）
│   └── prompt_food_v1.txt    # 视觉识别 Prompt（版本化管理）
├── lib/
│   ├── main.dart
│   ├── core/                 # router、theme、错误处理、常量
│   ├── domain/               # 纯 Dart，不 import Flutter，100% 单测覆盖
│   │   ├── tdee_calculator.dart
│   │   ├── traffic_light_engine.dart
│   │   └── nutrition_matcher.dart
│   ├── data/
│   │   ├── db/               # Drift 表定义与 DAO
│   │   └── providers/
│   │       ├── vision_provider.dart    # 协议 + Qwen + GLM + Mock 实现
│   │       ├── open_food_facts.dart
│   │       └── seed_loader.dart
│   └── features/
│       ├── onboarding/       # 首次启动引导（6 屏）
│       ├── home/             # 首页环形进度 + 今日餐次
│       ├── capture/          # 拍照/相册/裁剪
│       ├── recognition/      # 识别结果卡片、份量滑块、纠错、文字补充
│       ├── barcode/          # 扫码 + 拍营养表补录
│       ├── diary/            # 日记、历史日历
│       ├── stats/            # 周趋势图
│       └── settings/         # API Key、规则阈值、备份/恢复、关于
└── test/                     # domain 全量单测 + provider mock 测试
```

# 四、本地数据模型（Drift）

```sql
profile(id=1 单行, gender INTEGER, birth_year INTEGER, height_cm REAL, weight_kg REAL,
        activity_level INTEGER,        -- 1久坐~5重体力
        goal_type INTEGER,             -- 1减脂 2维持 3增肌
        goal_rate INTEGER,             -- 1=0.25kg 2=0.5kg 3=0.75kg 每周
        target_calories INTEGER, protein_g REAL, carbs_g REAL, fat_g REAL,  -- 自动算可手改
        allergies TEXT,                -- JSON 数组
        updated_at INTEGER, created_at INTEGER)

foods(id INTEGER PK, name TEXT, aliases TEXT,          -- JSON 数组，如 ["番茄炒蛋","西红柿炒蛋"]
      calories_per_100g REAL, protein_per_100g REAL, carbs_per_100g REAL, fat_per_100g REAL,
      fiber_per_100g REAL, sugar_per_100g REAL, sodium_per_100g REAL,
      serving_json TEXT,               -- {"碗":200,"盘":300} 克
      source INTEGER,                  -- 1种子库 2AI估算 3条码补录
      barcode TEXT UNIQUE, verified INTEGER DEFAULT 0, created_at INTEGER)

recognitions(id INTEGER PK, image_path TEXT,           -- 图片存应用私有目录，库内只存路径
             provider TEXT, latency_ms INTEGER, raw_json TEXT, created_at INTEGER)

recognition_items(id INTEGER PK, recognition_id INTEGER FK, detected_name TEXT,
                  confidence REAL, food_id INTEGER FK, est_grams INTEGER,
                  calories REAL, protein_g REAL, carbs_g REAL, fat_g REAL,
                  signal INTEGER,              -- 0绿 1黄 2红
                  advice_text TEXT, candidates_json TEXT,
                  corrected_food_id INTEGER, corrected_grams INTEGER)

meal_entries(id INTEGER PK, food_id INTEGER FK, grams INTEGER,
             meal_type INTEGER,                -- 1早 2午 3晚 4加餐
             logged_date TEXT,                 -- 'YYYY-MM-DD'
             calories REAL, protein_g REAL, carbs_g REAL, fat_g REAL, created_at INTEGER)

kv(key TEXT PK, value TEXT)                    -- 设置项、缓存、统计计数
```

# 五、关键设计

## 5.1 VisionProvider 协议

```dart
class VisionItem {
  final String name;          // 具体菜名（中文）
  final double confidence;    // 0~1
  final int estGrams;         // 估算克重
  final List<String> ingredients;
}
abstract class VisionProvider {
  String get name;
  Future<List<VisionItem>> analyze(File image);
}
// 实现：QwenVisionProvider / GlmVisionProvider / MockVisionProvider(测试用，返回固定数据)
// 调用链：主 provider(超时20s / 非200 / JSON解析失败) → 备 provider → 抛出友好错误"识别失败，请检查网络或 API 额度"
```

**图片预处理**：长边压缩 ≤1024px、JPEG 质量 80，base64 ≤ 300KB。

**Prompt（assets/prompt_food_v1.txt）要求**：只输出严格 JSON 数组（含 schema 与 2 个 few-shot：一盘中餐混合菜、一份西式简餐）；中餐份量锚定（一碗米饭≈200g、一盘炒菜≈250~300g）；不确定就降低 confidence，禁止编造；最多 8 项；temperature 0.1。

## 5.2 红黄绿灯引擎（domain/traffic_light_engine.dart）

纯函数，输入 item 营养值+克重、用户目标、当日已摄入汇总、禁忌列表；规则优先级自上而下、命中即停：

```
R1 命中禁忌/过敏 → 🔴"含你的禁忌食材：{x}"
R2 单品热量 > 当日剩余预算 → 🔴"这一份{cal}kcal，超过今天剩余的{budget}kcal预算"
R3 减脂 && (糖>20g/100g || 脂肪>20g/100g) → 🔴"高糖/高脂，减脂期不建议"
R4 蛋白质≥15g/100g && 脂肪≤10g/100g && 预算内 → 🟢"高蛋白低脂，今天蛋白质还差{gap}g，放心吃"
R5 热量 ≤ 剩余预算30% → 🟢"占今日预算{pct}%，在计划内"
R6 其他 → 🟡"可以吃，注意份量，建议{建议克重}g左右"
```

阈值集中在常量类，设置页可改。100% 单测覆盖全部规则及优先级冲突用例。

## 5.3 TDEE 计算（domain/tdee_calculator.dart）

Mifflin-St Jeor：男 BMR = 10×体重 + 6.25×身高 − 5×年龄 + 5；女 −161。活动系数 1.2/1.375/1.55/1.725/1.9。减脂按速率减 275/550/825 kcal；增肌加 300 kcal。蛋白质：减脂 2.0g/kg、其他 1.8g/kg；脂肪占总热量 25%；剩余为碳水。用户在结果确认页可手动修改，修改后不再自动覆盖。

## 5.4 营养库匹配（domain/nutrition_matcher.dart）

detected_name → foods.name 精确匹配 → aliases 匹配 → 模糊匹配（相似度 ≥0.6）→ 未命中：调大模型按标准做法估算每 100g 营养，入库 source=2、verified=0；设置页"待确认食物"列表供手动确认后 verified=1。

## 5.5 种子营养库（assets/seed_foods.json）

≥300 条：基础食材（鸡胸肉/糙米/鸡蛋/西兰花…，数据参照中国食物成分表）+ 高频中餐菜（番茄炒蛋/红烧肉/麻辣烫…）。首次启动导入，App 升级时按 name 做差量合并，不覆盖用户修改过的记录。

## 5.6 数据备份（刚需）

设置页"导出备份"：全库导出为 JSON，通过系统分享面板发出；"导入备份"反向恢复（导入前校验 schema 版本）。距上次备份 ≥7 天，首页顶部显示备份提醒横幅。

# 六、任务拆解（按序执行）

### Task 0 — 工程骨架
flutter create，接入 riverpod/go_router/dio/freezed/drift；GitHub Actions 跑 analyze+test。
**验收**：`flutter analyze` 零警告；`flutter test` 通过；CI 绿。

### Task 1 — 数据库 + 种子库导入
Drift 全部表 + DAO；seed_foods.json 先放 50 条打通流程；首次启动导入。
**验收**：DAO 增删改查单测通过；冷启动后 foods ≥50 条；重复启动不重复导入。

### Task 2 — 引导流程 + 目标引擎
6 屏 onboarding（性别年龄→身高体重→目标→速率→活动量→结果确认页可手改）写 profile；TDEE 纯函数+单测。
**验收**：输入"男/25/175cm/70kg/减脂/0.5kg每周/轻活动"，输出 1700~1900kcal、蛋白质 ≥130g；手改后重启不丢失不被覆盖。

### Task 3 — 设置页（API Key 管理）
DashScope key 必填才能使用识别；GLM key 选填；存 flutter_secure_storage；"测试连接"按钮发最小请求验证 key。
**验收**：无 key 时拍照页显示引导页而非报错；错误 key 提示"密钥无效"。

### Task 4 — 视觉识别链路（核心）
图片压缩 → VisionProvider 协议 + Qwen 实现 + GLM 降级 + Mock → JSON 解析 → 营养库匹配 → 红黄绿灯计算 → 写库。
**验收**：`tool/recognition_smoke.dart` 脚本用 test/fixtures/ 下 10 张真实中餐照片跑通且结构合法；主 provider 故障自动降级；Mock 下全部测试零真实 API 调用；真机 4G 端到端 P95 ≤5s。

### Task 5 — 拍照与结果页 UI
拍照/相册/裁剪 → loading（"正在识别，约3秒"）→ 结果卡片列表。每卡片：菜名、份量滑块（50g 步进，营养实时联动）、热量、三大营养素、红黄绿灯徽标、一句话理由；整餐合计条；低置信度（<0.7）黄条警示 + 候选列表点选纠正；"不对？纠正"支持换食物/改份量/文字补充后重识别；"存入今日"按餐次归档。
**验收**：限速 3G 下全流程每步有 loading/重试；滑块联动无闪烁；所有热量带"估算"角标。

### Task 6 — 首页 + 日记
首页环形进度（热量+三大营养素 vs 目标）+ 今日各餐卡片 + 大拍照按钮；日记日历（达标绿点/超标红点）；记录左滑删除。
**验收**：记录后即时刷新；当日汇总与明细求和误差 <1kcal；0 点跨天正确滚动。

### Task 7 — 条形码 + 补录 + 种子库补齐
扫码 → Open Food Facts → 命中展示营养+红绿灯；未命中引导拍营养成分表 → 大模型解析入库（source=3）。seed_foods.json 补齐至 ≥300 条。
**验收**：扫可乐命中；补录商品二次扫码直接命中。

### Task 8 — 打磨 + 备份 + 打包
空态/错误态文案；备份导出/导入全流程 + 7 天提醒；设置页显示本月识别次数与估算 API 花费（本地计数）；Android release 签名打包 APK。
**验收**：卸载重装后导入备份完整还原；真机全流程无崩溃。

# 七、需要项目所有者提供（仅 2 件）

1. 阿里云百炼 **DashScope API Key**（Task 3 前提供，未提供前用 Mock 开发不阻塞）
2. （可选）智谱 **API Key**，做降级备用

# 八、明确不做

不做：账号/登录、服务器、云同步、社区、食谱推荐、语音输入、可穿戴设备接入、自研模型、iOS 上架、多语言。遇到相关需求一律拒绝并在代码中标注 `TODO(out-of-scope)`。
