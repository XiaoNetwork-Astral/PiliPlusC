import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:PiliPlus/utils/cognitive_filter/ai/llm_provider.dart';
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

  /// 请求被取消：用户停手或后台开关关掉
  ///
  /// 不算网络失败，调用方不应重试，也不应当成错误提示给用户
  cancelled,

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

/// 聊天接口客户端，支持 OpenAI 兼容与 Anthropic Messages 两种格式
///
/// 只负责发送一个请求并归类错误，不做缓存与重试。代理与 dio 适配器复用
/// `jev_proxy.dart` 里的实现。
class LlmClient {
  LlmClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.format = LlmApiFormat.openai,
    this.timeout = const Duration(seconds: 60),
    JevProxy? proxy,
    this.temperature = 0.2,
    this.jsonMode = true,
    Dio? dio,
    CancelToken? cancelToken,
    this.onUsage,
    this.onReasoning,
  }) : _dio = dio ?? _createDio(proxy, timeout),
       _cancelToken = cancelToken;

  /// 接口根地址，例如 `https://api.example.com/v1`
  final String baseUrl;

  /// API Key，只在 Authorization 头里出现
  final String apiKey;

  /// 模型名
  final String model;

  /// 接口格式，默认 OpenAI 兼容
  final LlmApiFormat format;

  /// 连接、发送与接收超时
  final Duration timeout;

  /// 采样温度
  final double temperature;

  /// 是否要求服务商返回 JSON 对象
  final bool jsonMode;

  /// 取消令牌，取消后本客户端的请求立即结束并按 [LlmErrorKind.cancelled] 处理
  ///
  /// 非流式请求由 dio 取消；流式请求还会主动断开正在读的 SSE 连接
  final CancelToken? _cancelToken;

  /// 请求结束时回调本次的输入/输出 token 数
  ///
  /// 优先用 `usage.prompt_tokens` 与 `usage.completion_tokens`，Anthropic
  /// 的 `input_tokens` / `output_tokens` 同理；只有 `usage.total_tokens`
  /// 时按输入 0、输出=总数上报，避免漏记。
  /// 服务商没给 usage（或被取消、中途断流）时按字符数保守估算一次：
  /// 输入=提示字符总数，输出=已收到的正文与思考字符总数；一个字符按一个
  /// token 算会略微高估中文，方向是有意的。一个字节都没收到时不报。
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
      // 测试连接不记账，和以前一样
      metered: false,
    );
    return stopwatch.elapsed;
  }

  Future<String> _request(
    List<LlmMessage> messages, {
    int? maxTokens,
    bool? useJsonMode,
    bool think = true,
    bool metered = true,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const LlmException(LlmErrorKind.auth, '未填写 API Key');
    }
    final cancelToken = _cancelToken;
    if (cancelToken?.isCancelled ?? false) {
      throw _cancelledException();
    }
    final url = _chatUrl();
    // 只有整理请求（think 为真）且调用方要听思考时才走流式，测试连接
    // 仍用一次性的非流式请求
    final streaming = onReasoning != null && think;
    // DeepSeek 官方接口：整理用高强度思考（high），小模型不想清楚归不好类；
    // 测试连接只发一个很小的请求，思考会占满输出额度让正文为空，所以关掉。
    // 开着思考时不发 JSON 模式（文档没说两者能同时用），回复由解析器宽松处理。
    // 这个分支只在 OpenAI 格式下生效，Anthropic 格式不认这些字段
    final deepSeek =
        format == LlmApiFormat.openai && isDeepSeekHost(baseUrl);
    final body = buildLlmRequestBody(
      format: format,
      model: model,
      messages: <LlmPromptMessage>[
        for (final message in messages)
          (role: message.role, content: message.content),
      ],
      temperature: temperature,
      streaming: streaming,
      jsonMode: useJsonMode ?? jsonMode,
      think: think,
      deepSeek: deepSeek,
      maxTokens: maxTokens,
    );

    final meter = metered && onUsage != null
        ? _UsageMeter(onUsage: onUsage!, promptChars: _promptChars(messages))
        : null;

    if (streaming) {
      return _streamRequest(url, body, key: key, meter: meter);
    }

    try {
      final response = await _dio.post<String>(
        url,
        data: jsonEncode(body),
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.plain,
          headers: llmRequestHeaders(
            format: format,
            apiKey: key,
            streaming: false,
          ),
        ),
      );
      final content = _extractContent(
        response.data,
        format: format,
        secrets: <String>[key],
      );
      if (meter != null) {
        // 非流式拿不到思考增量，只把正文算作输出字符
        meter.addReceived(content);
        _reportUsageData(response.data, meter);
        meter.reportEstimate();
      }
      return content;
    } on DioException catch (error) {
      throw _mapDioError(error, secrets: <String>[key]);
    } on LlmException {
      rethrow;
    } catch (error) {
      if (cancelToken?.isCancelled ?? false) {
        throw _cancelledException();
      }
      // 原始异常可能带请求头或密钥，先脱敏再截断
      throw LlmException(
        LlmErrorKind.network,
        truncateError(redactSecrets(error.toString(), secrets: <String>[key])),
      );
    }
  }

  /// 提示消息的字符总数，用来在缺 usage 时估算输入 token
  static int _promptChars(List<LlmMessage> messages) {
    var count = 0;
    for (final message in messages) {
      count += message.content.length;
    }
    return count;
  }

  /// 流式请求：逐行读 SSE，思考增量交给 [onReasoning]，正文拼起来返回
  ///
  /// 一个网络块里可能有半行或多行，按换行缓冲成完整行再解析；没读到
  /// 结束标记（OpenAI 的 `[DONE]` 或 Anthropic 的 message_stop）、正文为空
  /// 都算解析失败。取消时主动断开正在读的流，不会把已收到的半截正文当成结果
  Future<String> _streamRequest(
    String url,
    Map<String, dynamic> body, {
    required String key,
    _UsageMeter? meter,
  }) async {
    final onReasoning = this.onReasoning;
    final cancelToken = _cancelToken;
    final content = StringBuffer();
    try {
      if (cancelToken?.isCancelled ?? false) {
        throw _cancelledException();
      }
      final Response<ResponseBody> response;
      try {
        response = await _dio.post<ResponseBody>(
          url,
          data: jsonEncode(body),
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            headers: llmRequestHeaders(
              format: format,
              apiKey: key,
              streaming: true,
            ),
          ),
        );
      } on DioException catch (error) {
        if (error.type == DioExceptionType.cancel ||
            (cancelToken?.isCancelled ?? false)) {
          throw _cancelledException();
        }
        // 非 2xx 的正文也是流，先读出来再套用与普通响应相同的映射
        throw await _mapStreamDioError(error, secrets: <String>[key]);
      } catch (error) {
        if (cancelToken?.isCancelled ?? false) {
          throw _cancelledException();
        }
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
      final pending = <int>[];
      Object? streamError;
      StackTrace? streamStack;
      final finished = Completer<void>();
      StreamSubscription<Uint8List>? subscription;
      subscription = responseBody.stream.listen(
        (chunk) {
          if (done || finished.isCompleted) {
            return;
          }
          try {
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
                meter: meter,
              )) {
                done = true;
                break;
              }
            }
            if (done) {
              unawaited(subscription?.cancel());
              if (!finished.isCompleted) {
                finished.complete();
              }
              return;
            }
            if (lineStart > 0) {
              pending.removeRange(0, lineStart);
            }
          } catch (error, stack) {
            streamError = error;
            streamStack = stack;
            unawaited(subscription?.cancel());
            if (!finished.isCompleted) {
              finished.complete();
            }
          }
        },
        onError: (Object error, StackTrace stack) {
          streamError = error;
          streamStack = stack;
          if (!finished.isCompleted) {
            finished.complete();
          }
        },
        onDone: () {
          if (!finished.isCompleted) {
            finished.complete();
          }
        },
        cancelOnError: true,
      );
      if (cancelToken != null) {
        // 取消时立即断开 SSE 读取，不等服务商自己结束
        unawaited(
          cancelToken.whenCancel.then((_) {
            if (finished.isCompleted) {
              return;
            }
            streamError = _cancelledException();
            streamStack = StackTrace.current;
            unawaited(subscription?.cancel());
            finished.complete();
          }),
        );
      }
      await finished.future;

      // 取消后不管读没读到结尾都作废，晚到的正文不再使用
      if (cancelToken?.isCancelled ?? false) {
        throw _cancelledException();
      }
      if (streamError != null) {
        final error = streamError!;
        if (error is DioException) {
          // 读到一半的接收超时仍是超时；其它中断按解析失败处理
          if (error.type == DioExceptionType.cancel) {
            throw _cancelledException();
          }
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
        }
        if (error is LlmException) {
          Error.throwWithStackTrace(error, streamStack ?? StackTrace.current);
        }
        throw _parseError(
          redactSecrets(error.toString(), secrets: <String>[key]),
          secrets: <String>[key],
          text: '流式响应中断',
        );
      }
      // 最后一行可能没有换行符，流结束后补处理
      if (!done && pending.isNotEmpty) {
        done = _handleSseLine(
          utf8.decode(pending, allowMalformed: true),
          content,
          onReasoning: onReasoning!,
          secrets: <String>[key],
          meter: meter,
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
    } finally {
      // 没拿到 usage 就按已收到的字符数保守估一次，取消、断流也算
      meter?.reportEstimate();
    }
  }

  /// 处理一行 SSE，返回是否读到结束标记
  bool _handleSseLine(
    String line,
    StringBuffer content, {
    required void Function(String delta) onReasoning,
    required List<String> secrets,
    _UsageMeter? meter,
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
    if (format == LlmApiFormat.anthropic) {
      return _handleAnthropicSseEvent(
        decoded,
        payload,
        content,
        onReasoning: onReasoning,
        secrets: secrets,
        meter: meter,
      );
    }
    // 带 usage 的分块可能没有 choices，先上报再跳过
    meter?.reportDecoded(decoded);
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
      meter?.addReceived(reasoning);
      onReasoning(reasoning);
    }
    final piece = delta['content'];
    if (piece is String) {
      meter?.addReceived(piece);
      content.write(piece);
    }
    return false;
  }

  /// 处理一个 Anthropic 流式事件，返回是否读到结束标记
  ///
  /// 文本与思考增量分别写入正文和回调；usage 分散在 message_start 的
  /// input_tokens 与 message_delta 的 output_tokens 里，由用量计数器合并。
  bool _handleAnthropicSseEvent(
    Map decoded,
    String payload,
    StringBuffer content, {
    required void Function(String delta) onReasoning,
    required List<String> secrets,
    _UsageMeter? meter,
  }) {
    switch (decoded['type']) {
      case 'message_start': {
        final message = decoded['message'];
        if (message is Map) {
          final usage = message['usage'];
          if (usage is Map) {
            meter?.reportInputTokens(_tokenOf(usage['input_tokens']));
          }
        }
        return false;
      }
      case 'content_block_start': {
        final block = decoded['content_block'];
        if (block is Map && block['type'] == 'text') {
          final text = block['text'];
          if (text is String && text.isNotEmpty) {
            meter?.addReceived(text);
            content.write(text);
          }
        }
        return false;
      }
      case 'content_block_delta': {
        final delta = decoded['delta'];
        if (delta is! Map) {
          return false;
        }
        switch (delta['type']) {
          case 'text_delta': {
            final text = delta['text'];
            if (text is String && text.isNotEmpty) {
              meter?.addReceived(text);
              content.write(text);
            }
          }
          case 'thinking_delta': {
            final thinking = delta['thinking'];
            if (thinking is String && thinking.isNotEmpty) {
              meter?.addReceived(thinking);
              onReasoning(thinking);
            }
          }
        }
        return false;
      }
      case 'message_delta': {
        final usage = decoded['usage'];
        if (usage is Map) {
          meter?.reportOutputTokens(_tokenOf(usage['output_tokens']));
        }
        final messageDelta = decoded['delta'];
        if (messageDelta is Map && messageDelta['stop_reason'] == 'refusal') {
          throw const LlmException(
            LlmErrorKind.refused,
            '服务商拒绝了这批内容（stop_reason: refusal）',
          );
        }
        return false;
      }
      case 'message_stop': {
        return true;
      }
      case 'error': {
        throw _anthropicError(decoded, payload, secrets: secrets);
      }
      default: {
        // ping、content_block_stop 等事件与正文无关，忽略
        return false;
      }
    }
  }

  /// 把 Anthropic 的 error 事件映射成现有的错误类别
  static LlmException _anthropicError(
    Map decoded,
    String payload, {
    required Iterable<String> secrets,
  }) {
    final error = decoded['error'];
    var type = '';
    var message = payload;
    if (error is Map) {
      final rawType = error['type'];
      if (rawType is String) {
        type = rawType;
      }
      final rawMessage = error['message'];
      if (rawMessage is String) {
        message = rawMessage;
      }
    }
    final detail = truncateError(
      redactSecrets(
        type.isEmpty ? message : '$type：$message',
        secrets: secrets,
      ),
    );
    return LlmException(
      switch (type) {
        'authentication_error' || 'permission_error' => LlmErrorKind.auth,
        'rate_limit_error' => LlmErrorKind.rateLimit,
        'invalid_request_error' => LlmErrorKind.refused,
        'overloaded_error' || 'api_error' => LlmErrorKind.server,
        _ => LlmErrorKind.server,
      },
      detail,
    );
  }

  /// 只读取整数 token 数，其它类型或负数返回 null
  static int? _tokenOf(Object? value) {
    if (value is! num) {
      return null;
    }
    final number = value.toDouble();
    if (!number.isFinite || number < 0) {
      return null;
    }
    return number.toInt();
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

  /// 拼出聊天接口地址，同时校验地址
  String _chatUrl() {
    final base = baseUrl.trim();
    if (!isValidApiBaseUrl(base)) {
      throw const LlmException(
        LlmErrorKind.network,
        '接口地址不正确，需以 http:// 或 https:// 开头',
      );
    }
    return buildChatUrl(base, format);
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
    required LlmApiFormat format,
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
    if (format == LlmApiFormat.anthropic) {
      return _extractAnthropicContent(decoded, data, secrets: secrets);
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

  /// 从 Anthropic 的非流式响应里拼接所有 text 块
  static String _extractAnthropicContent(
    Map decoded,
    String? data, {
    Iterable<String> secrets = const [],
  }) {
    if (decoded['type'] == 'error') {
      throw _anthropicError(decoded, data ?? '', secrets: secrets);
    }
    if (decoded['stop_reason'] == 'refusal') {
      throw const LlmException(
        LlmErrorKind.refused,
        '服务商拒绝了这批内容（stop_reason: refusal）',
      );
    }
    final content = decoded['content'];
    if (content is! List) {
      throw _parseError(data, secrets: secrets);
    }
    final buffer = StringBuffer();
    for (final block in content) {
      if (block is Map && block['type'] == 'text') {
        final text = block['text'];
        if (text is String) {
          buffer.write(text);
        }
      }
    }
    final text = buffer.toString();
    if (text.trim().isEmpty) {
      throw _parseError(
        data,
        secrets: secrets,
        text: '服务商返回的内容为空',
      );
    }
    return text;
  }

  /// 从成功响应里取 `usage` 上报；缺字段或结构不对就交给估算兜底
  static void _reportUsageData(String? data, _UsageMeter meter) {
    final Object? decoded;
    try {
      decoded = jsonDecode(data ?? '');
    } catch (_) {
      return;
    }
    meter.reportDecoded(decoded);
  }

  /// 取消请求时用的异常，消息不当作错误展示
  static LlmException _cancelledException() =>
      const LlmException(LlmErrorKind.cancelled, '请求已取消');

  /// 把 dio 异常映射成带原始信息的 [LlmException]
  ///
  /// 消息只描述接口/网络返回的原始信息，类别判定与消息文本无关。
  static LlmException _mapDioError(
    DioException error, {
    Iterable<String> secrets = const [],
  }) {
    final message = describeDioError(error, secrets: secrets);
    // 取消不是网络失败，先单独归类，免得落进下面的超时/网络分支
    if (error.type == DioExceptionType.cancel) {
      return _cancelledException();
    }
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
        return _cancelledException();
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

/// 一次请求的用量统计：有真实 usage 就用真实值，没有就按字符数估一次
///
/// 估算只在至少收到一段正文或思考之后才报；一个字节都没收到（例如连接
/// 失败、开始前就被取消）不报，避免把没发出去的请求记成费用
class _UsageMeter {
  _UsageMeter({required this.onUsage, required this.promptChars});

  final void Function(int inputTokens, int outputTokens)? onUsage;

  /// 提示消息的字符总数，估算时全部算作输入
  final int promptChars;

  /// 已收到的正文与思考字符数，估算时算作输出
  int receivedChars = 0;

  /// Anthropic 流式里 message_start 报的输入 token 数
  int? _inputTokens;

  /// Anthropic 流式里 message_delta 报的输出 token 数
  int? _outputTokens;

  bool _reported = false;

  /// 记录一段收到的正文或思考
  void addReceived(String text) {
    if (text.isNotEmpty) {
      receivedChars += text.length;
    }
  }

  /// 记录 Anthropic message_start 里的输入 token 数
  void reportInputTokens(int? tokens) {
    if (_reported || tokens == null) {
      return;
    }
    _inputTokens = tokens;
    _reportAnthropicUsage();
  }

  /// 记录 Anthropic message_delta 里的输出 token 数
  void reportOutputTokens(int? tokens) {
    if (_reported || tokens == null) {
      return;
    }
    _outputTokens = tokens;
    _reportAnthropicUsage();
  }

  /// 输入与输出都拿到后上报一次，只有一半时留给估算兜底
  void _reportAnthropicUsage() {
    final onUsage = this.onUsage;
    if (_reported || onUsage == null) {
      return;
    }
    final input = _inputTokens;
    final output = _outputTokens;
    if (input == null || output == null) {
      return;
    }
    _reported = true;
    onUsage(input, output);
  }

  /// 从已解码的分块里取 `usage` 上报，流式与非流式共用同一套语义
  ///
  /// `prompt_tokens` 与 `completion_tokens` 都是整数时按两者上报；
  /// Anthropic 的 `input_tokens` 与 `output_tokens` 同理；只有
  /// `total_tokens` 时按输入 0、输出=总数上报；字段缺失或类型不对时
  /// 不报，留给 [reportEstimate] 估算
  void reportDecoded(Object? decoded) {
    final onUsage = this.onUsage;
    if (_reported || onUsage == null || decoded is! Map) {
      return;
    }
    final usage = decoded['usage'];
    if (usage is! Map) {
      return;
    }
    final inputTokens = usage['prompt_tokens'];
    final outputTokens = usage['completion_tokens'];
    if (inputTokens is int && outputTokens is int) {
      _reported = true;
      onUsage(inputTokens, outputTokens);
      return;
    }
    final anthropicInput = usage['input_tokens'];
    final anthropicOutput = usage['output_tokens'];
    if (anthropicInput is int && anthropicOutput is int) {
      _reported = true;
      onUsage(anthropicInput, anthropicOutput);
      return;
    }
    final totalTokens = usage['total_tokens'];
    if (totalTokens is int) {
      _reported = true;
      onUsage(0, totalTokens);
    }
  }

  /// 没有真实 usage 时按字符数保守估算，只报一次
  void reportEstimate() {
    final onUsage = this.onUsage;
    if (_reported || onUsage == null || receivedChars <= 0) {
      return;
    }
    _reported = true;
    onUsage(promptChars, receivedChars);
  }
}
