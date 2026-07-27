// 自定义 OpenAI 兼容 provider 单测。
// 用 _FakeDio 拦截 POST，验证 postChat 的状态码/超时/解析路径
// （Qwen/GLM/Custom 共用此 mixin，测一次覆盖三者的 HTTP 逻辑）。
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paishiji/core/app_exceptions.dart';
import 'package:paishiji/data/providers/openai_compatible_provider.dart';

void main() {
  group('extractContent', () {
    test('content 是 String → 直接返回', () {
      final body =
          jsonDecode('{"choices":[{"message":{"content":"hello"}}]}')
              as Map<String, dynamic>;
      expect(extractContent(body), 'hello');
    });

    test('content 是 List<{text}> → 取第一段 text', () {
      final body =
          jsonDecode(
                '{"choices":[{"message":{"content":[{"type":"text","text":"hi"}]}}]}',
              )
              as Map<String, dynamic>;
      expect(extractContent(body), 'hi');
    });

    test('无 choices → 空串', () {
      expect(extractContent({}), '');
      expect(extractContent(null), '');
    });

    test('choices 空 list → 空串', () {
      final body = jsonDecode('{"choices":[]}') as Map<String, dynamic>;
      expect(extractContent(body), '');
    });
  });

  group('OpenAICompatibleProvider.postChat', () {
    test('200 + 合法 content → 返回文本', () async {
      final dio = _FakeDio(
        const _Response(200, {
          'choices': [
            {
              'message': {'content': '[{"name":"米饭"}]'},
            },
          ],
        }),
      );
      final p = _ProviderStub(
        baseUrl: 'https://api.example.com/v1/chat/completions',
        model: 'kimi-k2.7-code',
        apiKey: 'sk-test',
        dio: dio,
      );
      final content = await p.callPostChat(
        prompt: 'p',
        imageDataUrl: 'data:...',
      );
      expect(content, '[{"name":"米饭"}]');
      // 校验请求体形态
      expect(dio.lastPath, 'https://api.example.com/v1/chat/completions');
      final sent = dio.lastData as Map<String, dynamic>;
      expect(sent['model'], 'kimi-k2.7-code');
      final msg = (sent['messages'] as List).first as Map<String, dynamic>;
      final contentArr = msg['content'] as List;
      // 图片在前、文本在后
      expect((contentArr[0] as Map)['type'], 'image_url');
      expect((contentArr[1] as Map)['type'], 'text');
    });

    test('空 apiKey → InvalidKeyException（不触发降级）', () async {
      final p = _ProviderStub(
        baseUrl: 'https://x',
        model: 'm',
        apiKey: '   ',
        dio: _FakeDio(const _Response(200, {})),
      );
      expect(
        () => p.callPostChat(prompt: 'p', imageDataUrl: 'd'),
        throwsA(isA<InvalidKeyException>()),
      );
    });

    test('401 → InvalidKeyException', () async {
      final p = _ProviderStub(
        baseUrl: 'https://x',
        model: 'm',
        apiKey: 'sk-bad',
        dio: _FakeDio(const _Response(401, {})),
      );
      expect(
        () => p.callPostChat(prompt: 'p', imageDataUrl: 'd'),
        throwsA(isA<InvalidKeyException>()),
      );
    });

    test('403 → InvalidKeyException', () async {
      final p = _ProviderStub(
        baseUrl: 'https://x',
        model: 'm',
        apiKey: 'sk-bad',
        dio: _FakeDio(const _Response(403, {})),
      );
      expect(
        () => p.callPostChat(prompt: 'p', imageDataUrl: 'd'),
        throwsA(isA<InvalidKeyException>()),
      );
    });

    test('500 → VisionFailedException', () async {
      final p = _ProviderStub(
        baseUrl: 'https://x',
        model: 'm',
        apiKey: 'sk',
        dio: _FakeDio(const _Response(500, {})),
      );
      expect(
        () => p.callPostChat(prompt: 'p', imageDataUrl: 'd'),
        throwsA(isA<VisionFailedException>()),
      );
    });

    test('receiveTimeout → VisionFailedException(请求超时)', () async {
      final dio = _FakeDio.throws(
        DioException(
          type: DioExceptionType.receiveTimeout,
          requestOptions: RequestOptions(path: 'https://x'),
        ),
      );
      final p = _ProviderStub(
        baseUrl: 'https://x',
        model: 'm',
        apiKey: 'sk',
        dio: dio,
      );
      try {
        await p.callPostChat(prompt: 'p', imageDataUrl: 'd');
        fail('应抛异常');
      } on VisionFailedException catch (e) {
        expect(e.message, contains('超时'));
      }
    });
  });
}

/// 用最小桩实现 mixin，只测 postChat（不依赖 prompt 资源加载）。
class _ProviderStub with OpenAICompatibleProvider {
  _ProviderStub({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    required this.dio,
  });

  @override
  final String baseUrl;
  @override
  final String model;
  @override
  final String apiKey;
  @override
  final Dio dio;

  Future<String> callPostChat({
    required String prompt,
    required String imageDataUrl,
  }) => postChat(prompt: prompt, imageDataUrl: imageDataUrl);
}

/// 拦截 dio.post 的假实现。返回预设响应或抛预设异常。
class _FakeDio implements Dio {
  _FakeDio(this._resp) : _error = null;
  _FakeDio.throws(Object this._error) : _resp = null;

  final _Response? _resp;
  final Object? _error;

  dynamic lastPath;
  dynamic lastData;

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    lastPath = path;
    lastData = data;
    if (_error != null) throw _error;
    return _resp!.toResponse<T>();
  }

  // —— 以下 Dio 接口方法测试不用，noSuchName 兜底 ——
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response {
  const _Response(this.statusCode, this.data);
  final int statusCode;
  final Map<String, dynamic> data;

  Response<T> toResponse<T>() {
    return Response<T>(
      data: data as T,
      statusCode: statusCode,
      requestOptions: RequestOptions(path: ''),
    );
  }
}
