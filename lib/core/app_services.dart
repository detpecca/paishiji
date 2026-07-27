// 拍食记应用级服务容器：持有 DataScope + KeyVault + ConnectionTester + hasProfile 状态，
// go_router 用 refreshListenable 监听它做重定向。
//
// 另：在 bootstrap / onKeyChanged 时预解析 key 构造并缓存真实 provider 实例
// （VisionProvider / NutritionLabelProvider / NutritionEstimateProvider），
// 让 router builder（同步）能直接读缓存的 provider 而不必 await key 读取。
//
// 降级链顺序（自定义优先）：自定义 → DashScope → GLM → 无（router 回退 Mock）。
import 'package:flutter/foundation.dart';
import 'package:paishiji/data/data.dart';
import 'package:paishiji/data/providers/connection_tester.dart';
import 'package:paishiji/data/providers/key_vault.dart';
import 'package:paishiji/data/providers/nutrition_estimate_provider.dart';
import 'package:paishiji/data/providers/nutrition_label_provider.dart';
import 'package:paishiji/data/providers/vision_provider.dart';

/// 应用级全局状态。ChangeNotifier 让 go_router 在 hasProfile 变化时刷新路由。
class AppServices extends ChangeNotifier {
  AppServices(this._scope, this._keyVault, this._tester) {
    _refreshHasProfile();
  }

  final DataScope _scope;
  final KeyVault _keyVault;
  final ConnectionTester _tester;
  bool _hasProfile = false;
  bool _ready = false;
  bool _hasDashScopeKey = false;
  bool _hasCustomProvider = false;

  /// 缓存的真实 provider（按 key 预构造）。null 表示该链路无可用真实 provider，
  /// router / page 会回退到 Mock（不阻塞离线使用）。
  VisionProvider? _cachedVision;
  NutritionLabelProvider? _cachedLabel;
  NutritionEstimateProvider? _cachedEstimate;

  DataScope get data => _scope;
  KeyVault get keyVault => _keyVault;
  ConnectionTester get tester => _tester;
  bool get hasProfile => _hasProfile;
  bool get hasDashScopeKey => _hasDashScopeKey;
  bool get hasCustomProvider => _hasCustomProvider;

  /// 真实闸门：DashScope 或 自定义配置完整，任一为真即可拍照识别。
  bool get hasVisionKey => _hasDashScopeKey || _hasCustomProvider;

  bool get ready => _ready;

  /// 缓存的视觉识别 provider（自定义优先→DashScope→GLM）；null 则 router 回退 Mock。
  VisionProvider? get cachedVision => _cachedVision;
  NutritionLabelProvider? get cachedLabel => _cachedLabel;
  NutritionEstimateProvider? get cachedEstimate => _cachedEstimate;

  /// 启动初始化：种子导入 + 读 hasProfile + 读 key 存在性 + 预构造 provider。
  Future<void> bootstrap() async {
    await DataScope.ensureSeeded(_scope);
    await _refreshHasProfile();
    await _refreshKeyState();
    _ready = true;
    notifyListeners();
  }

  /// onboarding 提交后落 profile，并翻转 hasProfile。
  Future<void> commitProfile(ProfilesCompanion entry) async {
    await _scope.profileDao.upsert(entry);
    await _refreshHasProfile();
    notifyListeners();
  }

  /// 保存 key 后刷新可用性 + 重建 provider 缓存，通知 router。
  Future<void> onKeyChanged() async {
    await _refreshKeyState();
    notifyListeners();
  }

  Future<void> _refreshHasProfile() async {
    _hasProfile = (await _scope.profileDao.get()) != null;
  }

  Future<void> _refreshKeyState() async {
    final dash = await _keyVault.read(ApiKeyType.dashscope);
    final glm = await _keyVault.read(ApiKeyType.glm);
    final customRaw = await _keyVault.read(ApiKeyType.custom);
    final custom = CustomProviderConfig.tryParse(customRaw);

    _hasDashScopeKey = dash != null && dash.trim().isNotEmpty;
    _hasCustomProvider = custom?.isComplete ?? false;

    // 按降级顺序构造 provider 链：自定义优先 → DashScope → GLM。
    _cachedVision = _buildVisionChain(custom, dash, glm);
    _cachedLabel = _buildLabelChain(custom, dash, glm);
    _cachedEstimate = _buildEstimateChain(custom, dash);
  }

  /// 视觉识别降级链：自定义 → DashScope → GLM → null（router 回退 Mock）。
  VisionProvider? _buildVisionChain(
    CustomProviderConfig? custom,
    String? dash,
    String? glm,
  ) {
    final list = <VisionProvider>[
      if (custom != null && custom.isComplete)
        CustomVisionProvider(
          baseUrl: custom.baseUrl,
          model: custom.model,
          apiKey: custom.apiKey,
        ),
      if (dash != null && dash.trim().isNotEmpty)
        QwenVisionProvider(apiKey: dash),
      if (glm != null && glm.trim().isNotEmpty)
        GlmVisionProvider(apiKey: glm),
    ];
    if (list.isEmpty) return null;
    return VisionChain(primary: list.first, fallback: list.elementAtOrNull(1));
  }

  /// 营养表降级链：自定义 → DashScope → GLM → null。
  NutritionLabelProvider? _buildLabelChain(
    CustomProviderConfig? custom,
    String? dash,
    String? glm,
  ) {
    final list = <NutritionLabelProvider>[
      if (custom != null && custom.isComplete)
        CustomLabelProvider(
          baseUrl: custom.baseUrl,
          model: custom.model,
          apiKey: custom.apiKey,
        ),
      if (dash != null && dash.trim().isNotEmpty)
        QwenLabelProvider(apiKey: dash),
      if (glm != null && glm.trim().isNotEmpty)
        GlmLabelProvider(apiKey: glm),
    ];
    if (list.isEmpty) return null;
    return LabelChain(primary: list.first, fallback: list.elementAtOrNull(1));
  }

  /// 营养估算链：自定义 → DashScope → null（无 GLM estimate）。
  NutritionEstimateProvider? _buildEstimateChain(
    CustomProviderConfig? custom,
    String? dash,
  ) {
    if (custom != null && custom.isComplete) {
      return CustomEstimateProvider(
        baseUrl: custom.baseUrl,
        model: custom.model,
        apiKey: custom.apiKey,
      );
    }
    if (dash != null && dash.trim().isNotEmpty) {
      return QwenEstimateProvider(apiKey: dash);
    }
    return null;
  }

  /// 测试专用：基于临时 DataScope + 内存 KeyVault + Mock tester 构造。
  @visibleForTesting
  AppServices.forTesting(this._scope, this._keyVault, this._tester) {
    _refreshHasProfile();
    _refreshKeyState();
  }
}
