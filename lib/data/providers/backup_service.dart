// 拍食记数据备份服务。CLAUDE.md §5.6 / §六 Task 8：
// 设置页"导出备份"：全库导出为 JSON，share_plus 分享；
// "导入备份"：导入前校验 schema 版本，反向恢复。
// kv 存 last_backup_at，首页据此判断"距上次备份 ≥7 天"提醒。
//
// 纯协调：依赖 DataScope（各 DAO）。导出临时文件路径可注入 [pathGetter]
// 方便测试，避免真实文件系统副作用。
//
// JSON 字段名沿用 Drift 行类 toJson 的 camelCase（id/name/caloriesPer100g/...）。
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:meta/meta.dart';

import '../../core/app_exceptions.dart';
import '../../core/constants.dart';
import '../data.dart';

/// 备份失败。
class BackupException extends AppException {
  const BackupException([String? detail])
    : super('备份失败${detail == null ? '' : '：$detail'}');
}

/// 备份导出 JSON 的结构。版本号 [schemaVersion] 用于导入时校验。
class BackupPayload {
  const BackupPayload({
    required this.schemaVersion,
    required this.exportedAt,
    required this.profile,
    required this.foods,
    required this.recognitions,
    required this.recognitionItems,
    required this.mealEntries,
    required this.kv,
  });

  final int schemaVersion;
  final String exportedAt; // ISO8601
  final Map<String, dynamic>? profile;
  final List<Map<String, dynamic>> foods;
  final List<Map<String, dynamic>> recognitions;
  final List<Map<String, dynamic>> recognitionItems;
  final List<Map<String, dynamic>> mealEntries;
  final List<Map<String, dynamic>> kv;

  /// 序列化为 JSON 串。
  String toJson() => jsonEncode({
    'schema_version': schemaVersion,
    'exported_at': exportedAt,
    'profile': profile,
    'foods': foods,
    'recognitions': recognitions,
    'recognition_items': recognitionItems,
    'meal_entries': mealEntries,
    'kv': kv,
  });

  /// 反序列化 + schema 校验。失败返回 null。
  static BackupPayload? tryParse(String raw, {int? expectedSchemaVersion}) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final sv = m['schema_version'];
      if (sv is! int) return null;
      final want = expectedSchemaVersion ?? kBackupSchemaVersion;
      if (sv != want) return null;
      final exportedAt = m['exported_at']?.toString() ?? '';
      final profileRaw = m['profile'];
      return BackupPayload(
        schemaVersion: sv,
        exportedAt: exportedAt,
        profile: profileRaw is Map<String, dynamic>
            ? Map<String, dynamic>.from(profileRaw)
            : null,
        foods: _asList(m['foods']),
        recognitions: _asList(m['recognitions']),
        recognitionItems: _asList(m['recognition_items']),
        mealEntries: _asList(m['meal_entries']),
        kv: _asList(m['kv']),
      );
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, dynamic>> _asList(dynamic v) {
    if (v is! List) return const [];
    return v
        .whereType<Map<String, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}

/// 备份服务。注入 DataScope 与可选的 [now] / [pathGetter]。
class BackupService {
  BackupService(
    this.scope, {
    DateTime Function()? now,
    String Function(String fileName)? pathGetter,
  }) : _now = now ?? DateTime.now,
       _pathGetter = pathGetter ?? defaultBackupTempPath;

  final DataScope scope;
  final DateTime Function() _now;
  final String Function(String fileName) _pathGetter;

  /// 导出全库为 JSON 文件，返回文件路径。调用方用 share_plus 分享。
  Future<String> export() async {
    final profile = await scope.profileDao.get();
    final foods = await scope.foodsDao.all();
    final recognitions = await scope.recognitionsDao.allRecognitions();
    final recognitionItems = await scope.recognitionsDao.allItems();
    final mealEntries = await scope.mealEntriesDao.all();
    final kv = await scope.kvDao.all();

    final payload = BackupPayload(
      schemaVersion: kBackupSchemaVersion,
      exportedAt: _now().toIso8601String(),
      profile: profile?.toJson(),
      foods: foods.map((f) => f.toJson()).toList(),
      recognitions: recognitions.map((r) => r.toJson()).toList(),
      recognitionItems: recognitionItems.map((r) => r.toJson()).toList(),
      mealEntries: mealEntries.map((m) => m.toJson()).toList(),
      kv: kv.map((k) => k.toJson()).toList(),
    );

    final path = _pathGetter('paishiji-backup-${_stamp(_now())}.json');
    final file = File(path);
    await file.writeAsString(payload.toJson());
    // 记录备份时间（首页据此提醒）。
    await scope.kvDao.set(
      AppConstants.kvLastBackupAtKey,
      _now().toIso8601String(),
    );
    return path;
  }

  /// 导入备份：校验 schema → 清库 → 按顺序恢复（profile → foods →
  /// recognitions → recognition_items → meal_entries → kv）。
  /// 注意：导入是"覆盖恢复"，会清掉现有数据。调用方应先弹确认。
  Future<void> import(String raw) async {
    final payload = BackupPayload.tryParse(raw);
    if (payload == null) {
      throw const BackupException('文件格式或版本不匹配');
    }
    try {
      await scope.db.transaction(() async {
        // 清库：按外键反向删，避免引用约束失败。
        await scope.mealEntriesDao.deleteAll();
        await scope.recognitionsDao.deleteAllItems();
        await scope.recognitionsDao.deleteAll();
        await scope.foodsDao.deleteAll();
        await scope.profileDao.deleteAll();
        await scope.kvDao.deleteAll();

        // profile（单行）
        if (payload.profile != null) {
          await _restoreProfile(payload.profile!);
        }
        // foods（保留原 id，避免外键断裂）
        for (final f in payload.foods) {
          await _restoreFood(f);
        }
        // recognitions
        for (final r in payload.recognitions) {
          await _restoreRecognition(r);
        }
        // recognition_items
        for (final it in payload.recognitionItems) {
          await _restoreRecognitionItem(it);
        }
        // meal_entries
        for (final m in payload.mealEntries) {
          await _restoreMealEntry(m);
        }
        // kv
        for (final k in payload.kv) {
          await _restoreKv(k);
        }
      });
    } catch (e) {
      throw BackupException('$e');
    }
  }

  Future<void> _restoreProfile(Map<String, dynamic> m) async {
    await scope.profileDao.upsert(
      ProfilesCompanion.insert(
        id: m['id'] is int ? Value(m['id'] as int) : const Value(1),
        gender: m['gender'] as int,
        birthYear: m['birthYear'] as int,
        heightCm: (m['heightCm'] as num).toDouble(),
        weightKg: (m['weightKg'] as num).toDouble(),
        activityLevel: m['activityLevel'] as int,
        goalType: m['goalType'] as int,
        goalRate: m['goalRate'] as int,
        targetCalories: m['targetCalories'] as int,
        proteinG: (m['proteinG'] as num).toDouble(),
        carbsG: (m['carbsG'] as num).toDouble(),
        fatG: (m['fatG'] as num).toDouble(),
        allergies: Value(m['allergies']?.toString() ?? '[]'),
        updatedAt: _parseDate(m['updatedAt']) ?? _now(),
      ),
    );
  }

  Future<void> _restoreFood(Map<String, dynamic> m) async {
    await scope.foodsDao.restore(
      FoodsCompanion.insert(
        id: Value(m['id'] as int),
        name: m['name'] as String,
        aliases: Value(m['aliases']?.toString() ?? '[]'),
        caloriesPer100g: (m['caloriesPer100g'] as num).toDouble(),
        proteinPer100g: (m['proteinPer100g'] as num).toDouble(),
        carbsPer100g: (m['carbsPer100g'] as num).toDouble(),
        fatPer100g: (m['fatPer100g'] as num).toDouble(),
        fiberPer100g: Value((m['fiberPer100g'] as num?)?.toDouble() ?? 0),
        sugarPer100g: Value((m['sugarPer100g'] as num?)?.toDouble() ?? 0),
        sodiumPer100g: Value((m['sodiumPer100g'] as num?)?.toDouble() ?? 0),
        servingJson: Value(m['servingJson']?.toString() ?? '{}'),
        source: m['source'] as int,
        barcode: Value(m['barcode'] as String?),
        verified: Value(m['verified'] as int? ?? 0),
      ),
    );
  }

  Future<void> _restoreRecognition(Map<String, dynamic> m) async {
    await scope.recognitionsDao.restore(
      RecognitionsCompanion.insert(
        id: Value(m['id'] as int),
        imagePath: m['imagePath'] as String,
        provider: m['provider'] as String,
        latencyMs: Value(m['latencyMs'] as int?),
        rawJson: Value(m['rawJson'] as String?),
      ),
    );
  }

  Future<void> _restoreRecognitionItem(Map<String, dynamic> m) async {
    await scope.recognitionsDao.restoreItem(
      RecognitionItemsCompanion.insert(
        id: Value(m['id'] as int),
        recognitionId: m['recognitionId'] as int,
        detectedName: m['detectedName'] as String,
        confidence: (m['confidence'] as num).toDouble(),
        foodId: Value(m['foodId'] as int?),
        estGrams: m['estGrams'] as int,
        calories: (m['calories'] as num).toDouble(),
        proteinG: (m['proteinG'] as num).toDouble(),
        carbsG: (m['carbsG'] as num).toDouble(),
        fatG: (m['fatG'] as num).toDouble(),
        signal: m['signal'] as int,
        adviceText: Value(m['adviceText'] as String?),
        candidatesJson: Value(m['candidatesJson'] as String?),
        correctedFoodId: Value(m['correctedFoodId'] as int?),
        correctedGrams: Value(m['correctedGrams'] as int?),
      ),
    );
  }

  Future<void> _restoreMealEntry(Map<String, dynamic> m) async {
    await scope.mealEntriesDao.restore(
      MealEntriesCompanion.insert(
        id: Value(m['id'] as int),
        foodId: m['foodId'] as int,
        grams: m['grams'] as int,
        mealType: m['mealType'] as int,
        loggedDate: m['loggedDate'] as String,
        calories: (m['calories'] as num).toDouble(),
        proteinG: (m['proteinG'] as num).toDouble(),
        carbsG: (m['carbsG'] as num).toDouble(),
        fatG: (m['fatG'] as num).toDouble(),
      ),
    );
  }

  Future<void> _restoreKv(Map<String, dynamic> m) async {
    await scope.kvDao.set(m['key'] as String, m['value'] as String?);
  }

  static DateTime? _parseDate(dynamic v) {
    if (v is String) return DateTime.tryParse(v);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return null;
  }

  static String _stamp(DateTime n) =>
      '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}'
      '${n.hour.toString().padLeft(2, '0')}${n.minute.toString().padLeft(2, '0')}';
}

/// 默认临时目录：系统临时目录下 paishiji-backup-*.json。
/// 测试注入 [BackupService.pathGetter] 可绕过真实文件系统。
@visibleForTesting
String defaultBackupTempPath(String fileName) =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName';
