// 拍食记应用级服务容器：持有 DataScope + KeyVault + ConnectionTester + hasProfile 状态，
// go_router 用 refreshListenable 监听它做重定向。
import 'package:flutter/foundation.dart';
import 'package:paishiji/data/data.dart';
import 'package:paishiji/data/providers/connection_tester.dart';
import 'package:paishiji/data/providers/key_vault.dart';

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

  DataScope get data => _scope;
  KeyVault get keyVault => _keyVault;
  ConnectionTester get tester => _tester;
  bool get hasProfile => _hasProfile;
  bool get hasDashScopeKey => _hasDashScopeKey;
  bool get ready => _ready;

  /// 启动初始化：种子导入 + 读 hasProfile + 读 key 存在性。
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

  /// 保存 key 后刷新可用性，通知 router（capture 页据此判引导态/正常态）。
  Future<void> onKeyChanged() async {
    await _refreshKeyState();
    notifyListeners();
  }

  Future<void> _refreshHasProfile() async {
    _hasProfile = (await _scope.profileDao.get()) != null;
  }

  Future<void> _refreshKeyState() async {
    final dash = await _keyVault.read(ApiKeyType.dashscope);
    _hasDashScopeKey = dash != null && dash.trim().isNotEmpty;
  }

  /// 测试专用：基于临时 DataScope + 内存 KeyVault + Mock tester 构造。
  @visibleForTesting
  AppServices.forTesting(this._scope, this._keyVault, this._tester) {
    _refreshHasProfile();
    _refreshKeyState();
  }
}
