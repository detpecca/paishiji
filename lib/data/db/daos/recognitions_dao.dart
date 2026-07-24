import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

// 识别记录 + 识别项 DAO。
part 'recognitions_dao.g.dart';

@DriftAccessor(tables: [Recognitions, RecognitionItems])
class RecognitionsDao extends DatabaseAccessor<AppDatabase>
    with _$RecognitionsDaoMixin {
  RecognitionsDao(super.db);

  /// 一次识别：先写 recognitions 取 id，再批量写 items。
  Future<int> createRecognition({
    required String imagePath,
    required String provider,
    int? latencyMs,
    String? rawJson,
  }) => into(recognitions).insert(
    RecognitionsCompanion.insert(
      imagePath: imagePath,
      provider: provider,
      latencyMs: latencyMs == null ? const Value.absent() : Value(latencyMs),
      rawJson: rawJson == null ? const Value.absent() : Value(rawJson),
    ),
  );

  Future<void> addItems(List<RecognitionItemsCompanion> items) =>
      batch((b) => b.insertAll(recognitionItems, items));

  Future<List<RecognitionItem>> itemsOf(int recognitionId) => (select(
    recognitionItems,
  )..where((t) => t.recognitionId.equals(recognitionId))).get();

  /// 纠正识别项的 food 与 grams（"不对？纠正"换食物/改份量）。
  Future<void> applyCorrection({
    required int itemId,
    int? foodId,
    int? grams,
  }) => (recognitionItems.update()..where((t) => t.id.equals(itemId))).write(
    RecognitionItemsCompanion(
      correctedFoodId: foodId == null ? const Value.absent() : Value(foodId),
      correctedGrams: grams == null ? const Value.absent() : Value(grams),
    ),
  );
}
