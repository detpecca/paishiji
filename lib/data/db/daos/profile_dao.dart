import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

// 用户档案 DAO。profile 单行（id=1）。
part 'profile_dao.g.dart';

@DriftAccessor(tables: [Profiles])
class ProfileDao extends DatabaseAccessor<AppDatabase> with _$ProfileDaoMixin {
  ProfileDao(super.db);

  /// 读取单行档案。未建档返回 null。
  Future<Profile?> get() => select(profiles).getSingleOrNull();

  /// 首次建档或覆盖。onboarding 与"手改后不自动覆盖"由调用方控制何时调用。
  Future<void> upsert(ProfilesCompanion entry) =>
      into(profiles).insertOnConflictUpdate(entry);

  /// 只更新目标三宏量与 updatedAt（用户手改后调用，TDEE 不再覆盖）。
  Future<void> updateTargets({
    required int targetCalories,
    required double proteinG,
    required double carbsG,
    required double fatG,
    required DateTime updatedAt,
  }) => (profiles.update()..where((t) => t.id.equals(1))).write(
    ProfilesCompanion(
      targetCalories: Value(targetCalories),
      proteinG: Value(proteinG),
      carbsG: Value(carbsG),
      fatG: Value(fatG),
      updatedAt: Value(updatedAt),
    ),
  );

  /// 备份恢复：清空 profile（导入前调用）。
  Future<int> deleteAll() => profiles.delete().go();
}
