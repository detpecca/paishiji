// 拍食记拍照/相册/裁剪服务。CLAUDE.md §六 Task 5：拍照/相册/裁剪。
//
// 抽象 CaptureService + ImagePickerCaptureService(image_picker+image_cropper)
// + MockCaptureService(测试固定文件路径，零相机/相册依赖)。
// 返回裁剪后图片的文件路径，供 RecognitionPipeline 使用。
import 'dart:io';
import 'dart:ui';

import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:meta/meta.dart';

/// 拍照来源。
enum CaptureSource { camera, gallery }

/// 拍照/裁剪结果。
class CaptureResult {
  const CaptureResult({required this.path, this.source});
  final String path;
  final CaptureSource? source;
}

/// 拍照服务抽象。
abstract class CaptureService {
  Future<CaptureResult?> pickAndCrop(CaptureSource source);
}

/// 生产实现：image_picker 取图 → image_cropper 裁剪。
class ImagePickerCaptureService implements CaptureService {
  ImagePickerCaptureService({ImagePicker? picker, ImageCropper? cropper})
    : _picker = picker ?? ImagePicker(),
      _cropper = cropper ?? ImageCropper();

  final ImagePicker _picker;
  final ImageCropper _cropper;

  @override
  Future<CaptureResult?> pickAndCrop(CaptureSource source) async {
    final xfile = source == CaptureSource.camera
        ? await _picker.pickImage(source: ImageSource.camera, imageQuality: 80)
        : await _picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 80,
          );
    if (xfile == null) return null; // 用户取消
    final cropped = await _cropper.cropImage(
      sourcePath: xfile.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '裁剪餐盘',
          toolbarColor: const Color(0xFFE65100),
          toolbarWidgetColor: const Color(0xFFFFFFFF),
          lockAspectRatio: false,
        ),
        IOSUiSettings(title: '裁剪餐盘', aspectRatioLockEnabled: false),
      ],
    );
    final path = cropped?.path ?? xfile.path;
    return CaptureResult(path: path, source: source);
  }
}

/// 测试/离线实现：不碰相机/相册，返回固定路径。
/// pipeline 用 MockImageProcessor 不读真实文件，所以路径内容不影响测试。
@visibleForTesting
class MockCaptureService implements CaptureService {
  MockCaptureService({this.result});

  /// 设为 null 模拟"用户取消"；否则返回固定路径。
  final CaptureResult? result;

  @override
  Future<CaptureResult?> pickAndCrop(CaptureSource source) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return result;
  }
}

/// 退化兜底：某些测试环境无相机，只走相册。
File capturePathTo(String path) => File(path);
