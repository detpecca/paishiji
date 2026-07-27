# 拍食记

> 纯手机端个人饮食记录 APP —— 拍餐盘照片，视觉大模型识别食物、估算热量与宏量营养素，结合减脂/增肌目标给出 🟢推荐吃 / 🟡适量吃 / 🔴不建议吃。

[![CI](https://github.com/detpecca/paishiji/actions/workflows/ci.yml/badge.svg)](https://github.com/detpecca/paishiji/actions)
[![Tests](https://img.shields.io/badge/tests-196%20passed-brightgreen)](https://github.com/detpecca/paishiji)

## 特性

- **无服务器、无账号、无云同步** —— 一切数据和逻辑都在端上
- **拍照识别** —— 拍餐盘照片，视觉大模型识别食物成分 + 估算克重 + 热量与三大营养素
- **红黄绿灯引擎** —— 🟢推荐吃 / 🟡适量吃 / 🔴不建议吃，基于 TDEE 目标 + 当日已摄入 + 禁忌食材 + 营养密度
- **多 Provider 降级链** —— 主模型故障自动切备用，支持任意 OpenAI 兼容端点（如 Kimi）
- **条形码补录** —— 扫码查 Open Food Facts，未命中引导拍营养表大模型解析入库
- **本地 SQLite 库** —— 种子营养库 305 条（参照中国食物成分表），含差量合并
- **数据备份** —— 全库导出/导入 JSON，7 天未备份首页提醒
- **估算角标** —— UI 上所有热量数字带「估算」标识

## 技术栈

| 层 | 选型 |
|---|---|
| 框架 | Flutter 3.x（Dart），Android 优先 |
| 状态管理 | Riverpod 3.x + 原生 ChangeNotifier |
| 路由 | go_router |
| 本地数据库 | Drift（SQLite），类型安全编译期查询 |
| 网络 | dio（20s 超时 + 重试退避） |
| 数据类 | freezed + json_serializable |
| 视觉模型 | 阿里 Qwen-VL-Max（主）/ 智谱 GLM-4V（备）/ 任意 OpenAI 兼容端点（自定义，如 Kimi）|
| 条形码 | Open Food Facts（免费免密钥）|
| 扫码 | mobile_scanner |
| 图表 | fl_chart |
| 密钥存储 | flutter_secure_storage（Android Keystore）|
| 备份 | share_plus + file_picker |

## 快速开始

### 环境要求

- Flutter 3.x stable
- Android SDK（compileSdk 36, minSdk 23）
- Java 17（Android Studio JBR 自带）

### 开发运行

```bash
flutter pub get
flutter run                           # 连接 Android 设备/模拟器
```

### 测试

```bash
flutter analyze                       # 零警告
dart format --output=none --set-exit-if-changed .  # 格式化检查
flutter test                          # 196 个单测 + widget 测试，全 Mock 零真实 API
```

### 打包 release APK

```bash
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

签名配置读 `android/key.properties`（gitignore，需自备 keystore）。无 keystore 时退回 debug 签名。

## 配置 API Key

打开 APP → 走完 onboarding（设置身高体重目标）→ 设置页：

| 配置 | 用途 | 是否必填 |
|---|---|---|
| 阿里百炼 DashScope | 主视觉模型 | 任选其一即可（不填也能用 Mock 模式） |
| 智谱 GLM | 备用降级 | 选填 |
| 自定义 OpenAI 兼容端点 | 主视觉模型（覆盖 DashScope）| 选填，填 baseUrl+model+apiKey 三字段 |

**接入 Kimi 示例**：设置页「自定义 OpenAI 兼容端点」卡片 →
- Base URL: `https://api.kimi.com/coding/v1`（或官方 `https://api.moonshot.cn/v1`）
- 模型: `kimi-k2.7-code`
- API Key: 你的 Kimi key
- 测试连接 → 密钥有效 → 保存

填了自定义配置即为主 provider，故障降级到 DashScope，再降级到 GLM，都没有时回退 Mock（离线不崩）。详见 [CLAUDE.md §5.1](CLAUDE.md)。

## 项目结构

```
lib/
  core/        路由、主题、常量、AppServices（provider 缓存与降级链）
  domain/      纯 Dart（不依赖 Flutter/Drift），100% 单测
                 tdee_calculator / nutrition_matcher / traffic_light_engine
  data/        Drift DB + providers（HTTP/LLM/条码/备份/统计）+ DataScope 门面
  features/    UI 页 + 各自 ChangeNotifier view-model
                 onboarding / home / capture / recognition / barcode / diary / stats / settings
```

三个 LLM provider 抽象（Vision / Label / Estimate）共用 `OpenAICompatibleProvider` mixin，新增厂商零代码改动。

## 文档

- [CLAUDE.md](CLAUDE.md) —— 产品规格（技术实施文档，Task 0~8 来源）
- [CLAUDE.operational.md](CLAUDE.operational.md) —— 操作指南（命令、架构、构建坑、测试约定）

## 不做

账号/登录、服务器、云同步、社区、食谱推荐、语音输入、可穿戴设备、自研模型、iOS 上架、多语言。

## License

自用项目，未开源。© detpecca
