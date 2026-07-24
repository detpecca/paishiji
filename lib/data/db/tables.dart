import 'package:drift/drift.dart';

// 拍食记 Drift 表定义，严格对齐 CLAUDE.md §四本地数据模型。
// 红线#4：本地数据表均含 created_at 字段。

/// 用户档案（单行，id 固定 = 1）。
class Profiles extends Table {
  IntColumn get id => integer().clientDefault(() => 1)();
  IntColumn get gender => integer()(); // 1男 2女
  IntColumn get birthYear => integer()();
  RealColumn get heightCm => real()();
  RealColumn get weightKg => real()();
  IntColumn get activityLevel => integer()(); // 1久坐~5重体力
  IntColumn get goalType => integer()(); // 1减脂 2维持 3增肌
  IntColumn get goalRate => integer()(); // 1=0.25kg 2=0.5kg 3=0.75kg 每周
  IntColumn get targetCalories => integer()();
  RealColumn get proteinG => real()();
  RealColumn get carbsG => real()();
  RealColumn get fatG => real()();
  TextColumn get allergies =>
      text().withDefault(const Constant('[]'))(); // JSON 数组
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 营养库食物。
class Foods extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  TextColumn get aliases =>
      text().withDefault(const Constant('[]'))(); // JSON 数组
  RealColumn get caloriesPer100g => real()();
  RealColumn get proteinPer100g => real()();
  RealColumn get carbsPer100g => real()();
  RealColumn get fatPer100g => real()();
  RealColumn get fiberPer100g => real().withDefault(const Constant(0))();
  RealColumn get sugarPer100g => real().withDefault(const Constant(0))();
  RealColumn get sodiumPer100g => real().withDefault(const Constant(0))();
  TextColumn get servingJson =>
      text().withDefault(const Constant('{}'))(); // {"碗":200}
  IntColumn get source => integer()(); // 1种子库 2AI估算 3条码补录
  TextColumn get barcode => text().nullable()();
  IntColumn get verified => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {barcode},
  ];
}

/// 识别记录（一次调用对应一行）。
class Recognitions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get imagePath => text()();
  TextColumn get provider => text()();
  IntColumn get latencyMs => integer().nullable()();
  TextColumn get rawJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 识别项（一道菜对应一行）。
class RecognitionItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get recognitionId => integer().references(Recognitions, #id)();
  TextColumn get detectedName => text()();
  RealColumn get confidence => real()();
  IntColumn get foodId => integer().nullable().references(Foods, #id)();
  IntColumn get estGrams => integer()();
  RealColumn get calories => real()();
  RealColumn get proteinG => real()();
  RealColumn get carbsG => real()();
  RealColumn get fatG => real()();
  IntColumn get signal => integer()(); // 0绿 1黄 2红
  TextColumn get adviceText => text().nullable()();
  TextColumn get candidatesJson => text().nullable()();
  IntColumn get correctedFoodId => integer().nullable()();
  IntColumn get correctedGrams => integer().nullable()();
}

/// 餐次记录。
class MealEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get foodId => integer().references(Foods, #id)();
  IntColumn get grams => integer()();
  IntColumn get mealType => integer()(); // 1早 2午 3晚 4加餐
  TextColumn get loggedDate => text()(); // 'YYYY-MM-DD'
  RealColumn get calories => real()();
  RealColumn get proteinG => real()();
  RealColumn get carbsG => real()();
  RealColumn get fatG => real()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 简单 KV：设置项、缓存、统计计数、种子导入标志。
class Kv extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}
