// 拍食记图片预处理。CLAUDE.md §5.1：长边 ≤1024px、JPEG 质量 80、base64 ≤300KB。
//
// 抽象 ImageProcessor + DartImageProcessor(image 包) + MockImageProcessor。
// 纯函数式：输入 File/字节，输出处理后的 base64（含 data URL 前缀）。
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:meta/meta.dart';

import '../../core/constants.dart';

/// 预处理结果：base64 主体 + 可直接拼进 data URL 的前缀。
class ProcessedImage {
  const ProcessedImage({
    required this.base64,
    required this.dataUrl,
    this.width,
    this.height,
  });
  final String base64;
  final String dataUrl; // data:image/jpeg;base64,...
  final int? width;
  final int? height;
}

/// 图片预处理抽象。
abstract class ImageProcessor {
  /// 读文件 → 压缩 → base64。返回可直接 POST 的 data URL 内容。
  Future<ProcessedImage> processFile(File file);

  /// 字节 → 压缩 → base64。
  ProcessedImage processBytes(Uint8List bytes);
}

/// 生产实现：image 包解码 → 缩放 → JPEG 编码 → base64。
class DartImageProcessor implements ImageProcessor {
  const DartImageProcessor();

  @override
  Future<ProcessedImage> processFile(File file) async {
    final bytes = await file.readAsBytes();
    return processBytes(bytes);
  }

  @override
  ProcessedImage processBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      // 解码失败：留给上游报"图片格式不支持"。这里抛 ArgumentError。
      throw ArgumentError('无法解码图片，格式不支持');
    }
    final resized = _resizeLongEdge(decoded, AppConstants.imageMaxLongEdge);
    // 质量递降直到 base64 ≤ 300KB；从 q80 起，必要时降到 60/40/20。
    for (final q in const [80, 60, 40, 20]) {
      if (q > AppConstants.imageJpegQuality) continue; // 上限 80
      final jpg = img.encodeJpg(resized, quality: q);
      final b64 = _base64(jpg);
      if (b64.length <= AppConstants.imageMaxBase64Bytes || q == 20) {
        return ProcessedImage(
          base64: b64,
          dataUrl: 'data:image/jpeg;base64,$b64',
          width: resized.width,
          height: resized.height,
        );
      }
    }
    // 不应到达
    final jpg = img.encodeJpg(resized, quality: 20);
    final b64 = _base64(jpg);
    return ProcessedImage(
      base64: b64,
      dataUrl: 'data:image/jpeg;base64,$b64',
      width: resized.width,
      height: resized.height,
    );
  }

  /// 长边 ≤ maxEdge，按比例缩放；小图不放大。
  img.Image _resizeLongEdge(img.Image src, int maxEdge) {
    final w = src.width;
    final h = src.height;
    final longest = w > h ? w : h;
    if (longest <= maxEdge) return src;
    final scale = maxEdge / longest;
    final nw = (w * scale).round();
    final nh = (h * scale).round();
    return img.copyResize(src, width: nw, height: nh);
  }

  String _base64(Uint8List bytes) => _toBase64(bytes);
}

// 独立函数以便测试可注入不同编码行为。
String _toBase64(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// 测试 / 离线实现：固定字节 + 固定 base64，不解码真实图片。
/// 返回一个符合"≤300KB"约束的稳定 data URL，供 pipeline 走通。
@visibleForTesting
class MockImageProcessor implements ImageProcessor {
  const MockImageProcessor({this.base64 = 'mock-image-base64'});

  final String base64;

  @override
  Future<ProcessedImage> processFile(File file) async => _result();

  @override
  ProcessedImage processBytes(Uint8List bytes) => _result();

  ProcessedImage _result() => ProcessedImage(
    base64: base64,
    dataUrl: 'data:image/jpeg;base64,$base64',
    width: 1024,
    height: 768,
  );
}
