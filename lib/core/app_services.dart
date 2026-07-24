// 拍食记应用级服务容器：持有 DataScope + hasProfile 状态，
// go_router 用 refreshListenable 监听它做重定向。
import 'package:flutter/foundation.dart';
import 'package:paishiji/data/data.dart';

/// 应用级全局状态。ChangeNotifier 让 go_router 在 hasProfile 变化时刷新路由。
class AppServices extends ChangeNotifier {
  AppServices(this._scope) {
    _refreshHasProfile();
  }

  final DataScope _scope;
  bool _hasProfile = false;
  bool _ready = false;

  DataScope get data => _scope;
  bool get hasProfile => _hasProfile;
  bool get ready => _ready;

  /// 启动初始化：种子导入 + 读 hasProfile。
  Future<void> bootstrap() async {
    await DataScope.ensureSeeded(_scope);
    await _refreshHasProfile();
    _ready = true;
    notifyListeners();
  }

  /// onboarding 提交后落 profile，并翻转 hasProfile。
  Future<void> commitProfile(ProfilesCompanion entry) async {
    await _scope.profileDao.upsert(entry);
    await _refreshHasProfile();
    notifyListeners();
  }

  Future<void> _refreshHasProfile() async {
    _hasProfile = (await _scope.profileDao.get()) != null;
  }

  /// 测试专用：基于临时 DataScope 构造，便于挂内存库。
  @visibleForTesting
  AppServices.forTesting(this._scope) {
    _refreshHasProfile();
  }
}
