// 端上统一的友好错误类型。Provider 抽象抛出此类型，UI 直接展示 message。
class AppException implements Exception {
  const AppException(this.message);
  final String message;
  @override
  String toString() => message;
}

class NetworkException extends AppException {
  const NetworkException([String? detail])
    : super('网络异常，请稍后重试${detail == null ? '' : '：$detail'}');
}

class VisionFailedException extends AppException {
  const VisionFailedException([String? detail])
    : super('识别失败，请检查网络或 API 额度${detail == null ? '' : '：$detail'}');
}

class InvalidKeyException extends AppException {
  const InvalidKeyException() : super('密钥无效，请在设置页检查 API Key');
}
