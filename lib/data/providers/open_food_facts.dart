// 拍食记条码查询。CLAUDE.md §六 Task 7：
// 扫码 → Open Food Facts GET /api/v2/product/{barcode}.json → 命中展示营养+红绿灯。
//
// 抽象 OpenFoodFactsClient + HttpOpenFoodFactsClient(dio) + MockOpenFoodFactsClient。
// 免密钥免费接口（CLAUDE.md §二）。走公司代理 env（dio 默认读 HTTP_PROXY）。
//
// 红线#2：Mock 实现零真实 HTTP；测试可离线运行。
import 'package:dio/dio.dart';
import 'package:meta/meta.dart';

import '../../core/app_exceptions.dart';
import '../../core/constants.dart';
import '../../domain/nutrition_matcher.dart';

/// 条码查询结果。
class BarcodeResult {
  const BarcodeResult({
    required this.barcode,
    required this.name,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    this.sugarPer100g = 0,
    this.fiberPer100g = 0,
    this.sodiumPer100g = 0,
    this.imageUrl,
  });

  final String barcode;
  final String name;
  final double caloriesPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final double sugarPer100g;
  final double fiberPer100g;
  final double sodiumPer100g;
  final String? imageUrl;

  /// 转成 FoodRecord（用于入库 / 红绿灯）。
  FoodRecord toFoodRecord() => FoodRecord(
    id: 0,
    name: name,
    aliasesJson: '[]',
    caloriesPer100g: caloriesPer100g,
    proteinPer100g: proteinPer100g,
    carbsPer100g: carbsPer100g,
    fatPer100g: fatPer100g,
    sugarPer100g: sugarPer100g,
    fiberPer100g: fiberPer100g,
    sodiumPer100g: sodiumPer100g,
    barcode: barcode,
  );
}

/// 条码查询抽象。
abstract class OpenFoodFactsClient {
  Future<BarcodeResult?> lookup(String barcode);
}

/// 生产实现：dio GET Open Food Facts。
class HttpOpenFoodFactsClient implements OpenFoodFactsClient {
  HttpOpenFoodFactsClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  @override
  Future<BarcodeResult?> lookup(String barcode) async {
    final b = barcode.trim();
    if (b.isEmpty) return null;
    final url = '${AppConstants.openFoodFactsEndpoint}/$b.json';
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        url,
        queryParameters: {
          'fields':
              'product_name,generic_name,energy_100g,energy-kcal_100g,'
              'proteins_100g,carbohydrates_100g,fat_100g,sugars_100g,'
              'fiber_100g,sodium_100g,image_front_small_url',
        },
        options: Options(
          sendTimeout: AppConstants.networkTimeout,
          receiveTimeout: AppConstants.networkTimeout,
          validateStatus: (_) => true,
        ),
      );
      final code = resp.statusCode ?? 0;
      if (code != 200) return null;
      final data = resp.data;
      if (data == null) return null;
      final status = data['status'];
      if (status != 1) return null; // status_verbose == "product not found"
      final product = data['product'];
      if (product is! Map) return null;
      final name = (product['product_name'] ?? product['generic_name'] ?? '')
          .toString();
      if (name.trim().isEmpty) return null;
      // 营养字段：Open Food Facts 用 *_100g（克单位），能量 energy_100g 单位 kJ。
      final energyKj = _toDouble(product['energy_100g']);
      final energyKcal = energyKj > 0 ? energyKj / 4.184 : 0.0;
      final energyKcalDirect = _toDouble(product['energy-kcal_100g']);
      final calories = energyKcalDirect > 0 ? energyKcalDirect : energyKcal;
      final imageUrl = (product['image_front_small_url'] ?? '').toString();
      return BarcodeResult(
        barcode: b,
        name: name,
        caloriesPer100g: calories.toDouble(),
        proteinPer100g: _toDouble(product['proteins_100g']),
        carbsPer100g: _toDouble(product['carbohydrates_100g']),
        fatPer100g: _toDouble(product['fat_100g']),
        sugarPer100g: _toDouble(product['sugars_100g']),
        fiberPer100g: _toDouble(product['fiber_100g']),
        sodiumPer100g: _toDouble(product['sodium_100g']),
        imageUrl: imageUrl.isEmpty ? null : imageUrl,
      );
    } on DioException catch (e) {
      throw NetworkException(e.message ?? '条码查询失败');
    } catch (e) {
      throw NetworkException('$e');
    }
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

/// 测试 / 离线实现：按条码内容判定，零真实 HTTP（红线#2）。
/// 约定：常见条码命中；"not-found" / 未知码 → null；"net-error" → NetworkException。
@visibleForTesting
class MockOpenFoodFactsClient implements OpenFoodFactsClient {
  const MockOpenFoodFactsClient({this.latencyMs = 5});

  final int latencyMs;

  @override
  Future<BarcodeResult?> lookup(String barcode) async {
    await Future<void>.delayed(Duration(milliseconds: latencyMs));
    final b = barcode.trim();
    if (b == 'net-error') {
      throw const NetworkException('mock 网络异常');
    }
    return _mockProducts[b];
  }

  /// Mock 商品库（与真 Open Food Facts 字段一致；数据参照常见包装食品）。
  /// DoD 自验：扫可乐命中。
  static const _mockProducts = <String, BarcodeResult>{
    // 可口可乐 330ml 经典条码
    '5449000000997': BarcodeResult(
      barcode: '5449000000997',
      name: '可口可乐',
      caloriesPer100g: 42, // 每 100ml ≈ 42kcal
      proteinPer100g: 0,
      carbsPer100g: 10.6,
      fatPer100g: 0,
      sugarPer100g: 10.6,
      fiberPer100g: 0,
      sodiumPer100g: 0.004,
    ),
    // 可口可乐 500ml PET
    '5449000000218': BarcodeResult(
      barcode: '5449000000218',
      name: '可口可乐 500ml',
      caloriesPer100g: 42,
      proteinPer100g: 0,
      carbsPer100g: 10.6,
      fatPer100g: 0,
      sugarPer100g: 10.6,
      sodiumPer100g: 0.004,
    ),
    // 农夫山泉 550ml
    '6921168509256': BarcodeResult(
      barcode: '6921168509256',
      name: '农夫山泉饮用天然水',
      caloriesPer100g: 0,
      proteinPer100g: 0,
      carbsPer100g: 0,
      fatPer100g: 0,
      sugarPer100g: 0,
      sodiumPer100g: 0,
    ),
    // 伊利纯牛奶 250ml
    '6923190610012': BarcodeResult(
      barcode: '6923190610012',
      name: '伊利纯牛奶',
      caloriesPer100g: 64,
      proteinPer100g: 3.2,
      carbsPer100g: 4.8,
      fatPer100g: 3.6,
      sugarPer100g: 4.8,
      sodiumPer100g: 0.05,
    ),
  };
}
