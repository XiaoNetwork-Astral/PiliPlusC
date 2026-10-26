import 'dart:convert';

import 'package:PiliPlus/utils/cognitive_filter/jev_proxy.dart';
import 'package:PiliPlus/utils/cognitive_filter/raw_error.dart';
import 'package:dio/dio.dart';

/// 大模型调用失败的类别
enum LlmErrorKind {
  /// 401/403：密钥无效或没有权限
  auth,

  /// 429：请求过于频繁
  rateLimit,

  /// 服务商拒绝处理这批内容
  refused,

  /// 连接、发送或接收超时
  timeout,

  /// 连接失败、证书或 DNS 错误
  network,

  /// 5xx：服务端错误
  server,

  /// 返回结构不对或内容为空
  parse,

  /// 已达整理接口的今日费用上限
  budget,
}

/// 大模型调用异常
///
/// [message] 是给用户看的简短说明，可能是接口/网络的原始信息（状态码、
/// 响应正文片段、异常类型和消息），不含 Authorization 头或密钥。
class LlmException implements Exception {
  const LlmException(this.kind, this.message, {this.statusCode});

  final LlmErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() {
    final status = statusCode == null ? '' : '，HTTP $statusCode';
    return 'LlmException(${kind.name}$status): $message';
  }
}

/// 给编排层用的聊天函数：传入消息，返回模型输出的文本
typedef LlmChat = Future<String> Function(List<LlmMessage> messages);

/// 一条对话消息，[role] 为 system 或 user
class LlmMessage {
  const LlmMessage({required this.role, required this.content});

  final String role;
  final String content;
}

/// OpenAI 兼容的聊天接口客户端
///
/// 只负责发送一个请求并归类错误，不做缓存与重试。代理与 dio 适配器复用
/// `jev_proxy.dart` 里的实现。
class LlmClient {
  LlmClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.timeout = const Duration(seconds: 60),
    JevProxy? proxy,
    this.temperature = 0.2,
    this.jsonMode = true,
    Dio? dio,
    this.onUsage,
    this.onReasoning,
  }) : _dio = dio ?? _createDio(proxy, timeout);

  /// 接口根地址，例如 `https://api.example.com/v1`
  final String baseUrl;

  /// API Key，只在 Authorization 头里出现
  final String apiKey;

  /// 模型名
  final String model;

  /// 连接、发送与接收超时
  final Duration timeout;

  /// 采样温度
  final double temperature;

  /// 是否要求服务商返回 JSON 对象
  final bool jsonMode;

  /// 成功拿到响应后回调本次的输入/输出 token 数，取不到时不回调
  ///
  /// 优先用 `usage.prompt_tokens` 与 `usage.completion_tokens`；只有
  /// `usage.total_tokens` 时按输入 0、输出=总数上报，避免漏记。
  final void Function(int inputTokens, int outputTokens)? onUsage;

  /// 流式响应里每段非空的思考文字到达时回调
  ///
  /// 非 null 时整理请求改用流式读取，边想边把增量交给界面；为 null 时
  /// 保持原来的非流式路径
  final void Function(String delta)? onReasoning;

  final Dio _dio;

  /// 换行符的字节值，流式正文按它切行
  static const int _lineFeed = 0x0A;

  static Dio _createDio(JevProxy? proxy, Duration timeout) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: timeout,
        sendTimeout: timeout,
        receiveTimeout: timeout,
      ),
    );
    if (proxy != null && proxy.type != JevProxyType.none) {
      dio.httpClientAdapter = createJevAdapter(proxy, timeout: timeout);
    }
    return dio;
  }

  /// 发一次聊天请求，返回 `choices[0].message.content`
  Future<String> chat(List<LlmMessage> messages) => _request(messages);

  /// 发一个最小请求测试连通性，返回从发请求到拿到有效响应的耗时
  ///
  /// 失败仍抛 [LlmException]。
  Future<Duration> test() async {
    final stopwatch = Stopwatch()..start();
    await _request(
      const <LlmMessage>[LlmMessage(role: 'user', content: '回复 ok')],
      maxTokens: 16,
      useJsonMode: false,
      think: false,
    );
    return stopwatch.elapsed;
  }

  Future<String> _request(
    List<LlmMessage> messages, {
    int? maxTokens,
    bool? useJsonMode,
    bool think = true,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const LlmException(LlmErrorKind.auth, '未填写 API Key');
    }
    final url = _chatUrl();
    // 只有整理请求（think 为真）且调用方要听思考时才走流式，测试连接
    // 仍用一次性的非流式请求
    final streaming = onReasoning != null && think;
    final body = <String, dynamic>{
      'model': model,
      'messages': <Map<String, dynamic>>[
        for (final message in messages)
          <String, dynamic>{'role': message.role, 'content': message.content},
      ],
      'temperature': temperature,
      'stream': streaming,
    };
    if (streaming) {
      // 让服务商在流末尾补一个带 usage 的分块，费用仍能照常统计
      body['stream_options'] = const <String, dynamic>{
        'include_usage': true,
      };
    }
    // DeepSeek 官方接口：整理用最高强度的思考，小模型不想清楚归不好类；
    // 测试连接只发一个很小的请求，思考会占满输出额度让正文为空，所以关掉。
    // 开着思考时不发 JSON 模式（文档没说两者能同时用），回复由解析器宽松处理。
    // 其它服务商不认这些字段，一概不发
    final deepseek =
        Uri.tryParse(baseUrl.trim())?.host.endsWith('deepseek.com') ?? false;
    if (deepseek) {
      if (think) {
        body['thinking'] = const <String, dynamic>{'type': 'enabled'};
        body['reasoning_effort'] = 'max';
      } else {
        body['thinking'] = const <String, dynamic>{'type': 'disabled'};
      }
    }
    if ((useJsonMode ?? jsonMode) && !(deepseek && think)) {
      body['response_format'] = const <String, dynamic>{'type': 'json_object'};
    }
    if (maxTokens != null) {
      body['max_tokens'] = maxTokens;
    }

    if (streaming) {
      return _streamRequest(url, body, key: key);
    }

    try {
      final response = await _dio.post<String>(
        url,
        data: jsonEncode(body),
        options: Options(
          responseType: ResponseType.plain,
          headers: <String, dynamic>{
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );
      final content = _extractContent(response.data, secrets: <String>[key]);
      _reportUsage(response.data);
      return content;
    } on DioException catch (error) {
      throw _mapDioError(error, secrets: <String>[key]);
    } on LlmException {
      rethrow;
    } catch (error) {
      // 原始异常可能带请求头或密钥，先脱敏再截断
      throw LlmException(
        LlmErrorKind.network,
        truncateError(redactSecrets(error.toString(), secrets: <String>[key])),
      );
    }
  }

  /// 流式请求：逐行读 SSE，思考增量交给 [onReasoning]，正文拼起来返回
  ///
  /// 一个网络块里可能有半行或多行，按换行缓冲成完整行再解析；没读到
  /// `[DONE]` 就断流、正文为空都算解析失败
  Future<String> _streamRequest(
    String url,
    Map<String, dynamic> body, {
    required String key,
  }) async {
    final onReasoning = this.onReasoning;
    final content = StringBuffer();
    final Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        url,
        data: jsonEncode(body),
        options: Options(
          responseType: ResponseType.stream,
          headers: <String, dynamic>{
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          },
        ),
      );
    } on DioException catch (error) {
      // 非 2xx 的正文也是流，先读出来再套用与普通响应相同的映射
      throw await _mapStreamDioError(error, secrets: <String>[key]);
    } catch (error) {
      throw LlmException(
        LlmErrorKind.network,
        truncateError(redactSecrets(error.toString(), secrets: <String>[key])),
      );
    }

    final responseBody = response.data;
    if (responseBody == null) {
      throw _parseError(
        null,
        secrets: <String>[key],
        text: '服务商返回的内容为空',
      );
    }

    var done = false;
    try {
      final pending = <int>[];
      await for (final chunk in responseBody.stream) {
        pending.addAll(chunk);
        var lineStart = 0;
        for (var index = 0; index < pending.length; index++) {
          if (pending[index] != _lineFeed) {
            continue;
          }
          final line = utf8.decode(
            pending.sublist(lineStart, index),
            allowMalformed: true,
          );
          lineStart = index + 1;
          if (_handleSseLine(
            line,
            content,
            onReasoning: onReasoning!,
            secrets: <String>[key],
          )) {
            done = true;
            break;
          }
        }
        if (done) {
          break;
        }
        if (lineStart > 0) {
          pending.removeRange(0, lineStart);
        }
      }
      // 最后一行可能没有换行符，流结束后补处理
      if (!done && pending.isNotEmpty) {
        done = _handleSseLine(
          utf8.decode(pending, allowMalformed: true),
          content,
          onReasoning: onReasoning!,
          secrets: <String>[key],
        );
      }
    } on DioException catch (error) {
      // 读到一半的接收超时仍是超时；其它中断按解析失败处理
      if (error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        throw _mapDioError(error, secrets: <String>[key]);
      }
      throw _parseError(
        redactSecrets(error.toString(), secrets: <String>[key]),
        secrets: <String>[key],
        text: '流式响应中断',
      );
    } on LlmException {
      rethrow;
    } catch (error) {
      throw _parseError(
        redactSecrets(error.toString(), secrets: <String>[key]),
        secrets: <String>[key],
        text: '流式响应中断',
      );
    }

    if (!done) {
      throw const LlmException(LlmErrorKind.parse, '流式响应意外结束');
    }
    final text = content.toString();
    if (text.trim().isEmpty) {
      throw _parseError(
        null,
        secrets: <String>[key],
        text: '服务商返回的内容为空',
      );
    }
    return text;
  }

  /// 处理一行 SSE，返回是否读到结束标记
  bool _handleSseLine(
    String line,
    StringBuffer content, {
    required void Function(String delta) onReasoning,
    required List<String> secrets,
  }) {
    final text = line.trim();
    if (!text.startsWith('data:')) {
      return false;
    }
    final payload = text.substring(5).trim();
    if (payload.isEmpty) {
      return false;
    }
    if (payload == '[DONE]') {
      return true;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      throw _parseError(
        payload,
        secrets: secrets,
        text: '流式返回的内容不是合法 JSON',
      );
    }
    if (decoded is! Map) {
      throw _parseError(payload, secrets: secrets);
    }
    // 带 usage 的分块可能没有 choices，先上报再跳过
    _reportUsageValue(decoded);
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      return false;
    }
    final choice = choices.first;
    if (choice is! Map) {
      throw _parseError(payload, secrets: secrets);
    }
    if (choice['finish_reason'] == 'content_filter') {
      throw const LlmException(
        LlmErrorKind.refused,
        '服务商拒绝了这批内容（finish_reason: content_filter）',
      );
    }
    final delta = choice['delta'];
    if (delta is! Map) {
      return false;
    }
    final reasoning = delta['reasoning_content'];
    if (reasoning is String && reasoning.isNotEmpty) {
      onReasoning(reasoning);
    }
    final piece = delta['content'];
    if (piece is String) {
      content.write(piece);
    }
    return false;
  }

  /// 把流式错误响应体读成文本，再交给 [_mapDioError]
  static Future<LlmException> _mapStreamDioError(
    DioException error, {
    required List<String> secrets,
  }) async {
    final response = error.response;
    final data = response?.data;
    if (data is! ResponseBody) {
      return _mapDioError(error, secrets: secrets);
    }
    var body = '';
    try {
      final bytes = <int>[];
      await for (final chunk in data.stream) {
        bytes.addAll(chunk);
      }
      body = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      // 错误正文读不出来时只保留状态码，消息格式仍与非流式一致
    }
    return _mapDioError(
      error.copyWith(
        response: Response<String>(
          requestOptions: error.requestOptions,
          data: body,
          statusCode: response?.statusCode,
          statusMessage: response?.statusMessage,
          isRedirect: response?.isRedirect ?? false,
          redirects: response?.redirects ?? const [],
          extra: response?.extra,
          headers: response?.headers,
        ),
      ),
      secrets: secrets,
    );
  }

  /// 拼出 `${baseUrl 去掉末尾斜杠}/chat/completions`，同时校验地址
  String _chatUrl() {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(base);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const LlmException(
        LlmErrorKind.network,
        '接口地址不正确，需以 http:// 或 https:// 开头',
      );
    }
    return '$base/chat/completions';
  }

  /// 构造解析失败异常，说明后追加响应正文片段；取不到正文时只保留说明
  static LlmException _parseError(
    String? data, {
    Iterable<String> secrets = const [],
    String text = '服务商返回的结构不正确',
  }) {
    final fragment = data == null
        ? ''
        : truncateError(redactSecrets(data, secrets: secrets));
    return LlmException(
      LlmErrorKind.parse,
      fragment.isEmpty ? text : '$text：$fragment',
    );
  }

  /// 从响应 JSON 里取出内容，结构不对或内容为空都算解析失败
  static String _extractContent(
    String? data, {
    Iterable<String> secrets = const [],
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(data ?? '');
    } on FormatException {
      throw _parseError(
        data,
        secrets: secrets,
        text: '服务商返回的内容不是合法 JSON',
      );
    }
    if (decoded is! Map) {
      throw _parseError(data, secrets: secrets);
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw _parseError(data, secrets: secrets);
    }
    final choice = choices.first;
    if (choice is! Map) {
      throw _parseError(data, secrets: secrets);
    }
    if (choice['finish_reason'] == 'content_filter') {
      throw const LlmException(
        LlmErrorKind.refused,
        '服务商拒绝了这批内容（finish_reason: content_filter）',
      );
    }
    final message = choice['message'];
    if (message is! Map) {
      throw _parseError(data, secrets: secrets);
    }
    final content = message['content'];
    if (content is! String || content.trim().isEmpty) {
      throw _parseError(
        data,
        secrets: secrets,
        text: '服务商返回的内容为空',
      );
    }
    return content;
  }

  /// 从成功响应里取 `usage` 上报；缺字段或结构不对就跳过
  ///
  /// `prompt_tokens` 与 `completion_tokens` 都是整数时按两者上报；只有
  /// `total_tokens` 时按输入 0、输出=总数上报，免得整次调用不计费。
  void _reportUsage(String? data) {
    if (onUsage == null) {
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(data ?? '');
    } catch (_) {
      return;
    }
    _reportUsageValue(decoded);
  }

  /// 从已解码的分块里取 `usage` 上报，流式与非流式共用同一套语义
  void _reportUsageValue(Object? decoded) {
    final onUsage = this.onUsage;
    if (onUsage == null) {
      return;
    }
    if (decoded is! Map) {
      return;
    }
    final usage = decoded['usage'];
    if (usage is! Map) {
      return;
    }
    final inputTokens = usage['prompt_tokens'];
    final outputTokens = usage['completion_tokens'];
    if (inputTokens is int && outputTokens is int) {
      onUsage(inputTokens, outputTokens);
      return;
    }
    final totalTokens = usage['total_tokens'];
    if (totalTokens is int) {
      onUsage(0, totalTokens);
    }
  }

  /// 把 dio 异常映射成带原始信息的 [LlmException]
  ///
  /// 消息只描述接口/网络返回的原始信息，类别判定与消息文本无关。
  static LlmException _mapDioError(
    DioException error, {
    Iterable<String> secrets = const [],
  }) {
    final message = describeDioError(error, secrets: secrets);
    final status = error.response?.statusCode;
    if (status != null) {
      if (status == 401 || status == 403) {
        return LlmException(
          LlmErrorKind.auth,
          message,
          statusCode: status,
        );
      }
      if (status == 429) {
        return LlmException(
          LlmErrorKind.rateLimit,
          message,
          statusCode: status,
        );
      }
      if (status >= 500) {
        return LlmException(
          LlmErrorKind.server,
          message,
          statusCode: status,
        );
      }
      // 400/422 表示请求被拒（正文常带 content/risk/policy/sensitive/违规/敏感
      // 等字样），451 同理；这些批的条目确定处理不了，重试后丢弃
      if (status == 400 || status == 422 || status == 451) {
        return LlmException(
          LlmErrorKind.refused,
          message,
          statusCode: status,
        );
      }
      // 其余 4xx（例如接口路径写错）不当作内容被拒，避免误删收集池
      return LlmException(
        LlmErrorKind.network,
        message,
        statusCode: status,
      );
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return LlmException(LlmErrorKind.timeout, message);
      case DioExceptionType.badCertificate:
        return LlmException(LlmErrorKind.network, message);
      case DioExceptionType.cancel:
        return LlmException(LlmErrorKind.network, message);
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return LlmException(LlmErrorKind.network, message);
      case DioExceptionType.badResponse:
        return _parseError(
          error.response?.data?.toString(),
          secrets: secrets,
        );
      default:
        return LlmException(LlmErrorKind.network, message);
    }
  }
}
