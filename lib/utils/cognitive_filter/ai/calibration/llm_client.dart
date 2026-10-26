import 'dart:convert';

import 'package:PiliPlus/utils/cognitive_filter/jev_proxy.dart';
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

  /// 已达整理接口的今日 token 用量上限
  budget,
}

/// 大模型调用异常，[message] 是中文且不含 Authorization 头或密钥
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

  /// 成功拿到响应后回调本次的 `usage.total_tokens`，取不到时不回调
  final void Function(int totalTokens)? onUsage;

  final Dio _dio;

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

  /// 发一个最小请求测试连通性，失败抛 [LlmException]
  Future<void> test() async {
    await _request(
      const <LlmMessage>[LlmMessage(role: 'user', content: '回复 ok')],
      maxTokens: 16,
      useJsonMode: false,
      think: false,
    );
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
    final body = <String, dynamic>{
      'model': model,
      'messages': <Map<String, dynamic>>[
        for (final message in messages)
          <String, dynamic>{'role': message.role, 'content': message.content},
      ],
      'temperature': temperature,
      'stream': false,
    };
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
      final content = _extractContent(response.data);
      _reportUsage(response.data);
      return content;
    } on DioException catch (error) {
      throw _mapDioError(error);
    } on LlmException {
      rethrow;
    } catch (_) {
      // 不拼接原始异常，避免把请求头或密钥带进日志
      throw const LlmException(LlmErrorKind.network, '网络错误，请检查网络或代理');
    }
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

  static const LlmException _parseError = LlmException(
    LlmErrorKind.parse,
    '服务商返回的结构不正确',
  );

  /// 从响应 JSON 里取出内容，结构不对或内容为空都算解析失败
  static String _extractContent(String? data) {
    final Object? decoded;
    try {
      decoded = jsonDecode(data ?? '');
    } on FormatException {
      throw const LlmException(LlmErrorKind.parse, '服务商返回的内容不是合法 JSON');
    }
    if (decoded is! Map) {
      throw _parseError;
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw _parseError;
    }
    final choice = choices.first;
    if (choice is! Map) {
      throw _parseError;
    }
    if (choice['finish_reason'] == 'content_filter') {
      throw const LlmException(LlmErrorKind.refused, '服务商拒绝了这批内容');
    }
    final message = choice['message'];
    if (message is! Map) {
      throw _parseError;
    }
    final content = message['content'];
    if (content is! String || content.trim().isEmpty) {
      throw _parseError;
    }
    return content;
  }

  /// 从成功响应里取 `usage.total_tokens` 上报；缺字段或结构不对就跳过
  void _reportUsage(String? data) {
    final onUsage = this.onUsage;
    if (onUsage == null) {
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(data ?? '');
    } catch (_) {
      return;
    }
    if (decoded is! Map) {
      return;
    }
    final usage = decoded['usage'];
    if (usage is! Map) {
      return;
    }
    final totalTokens = usage['total_tokens'];
    if (totalTokens is int) {
      onUsage(totalTokens);
    }
  }

  /// 把 dio 异常映射成带中文 message 的 [LlmException]
  static LlmException _mapDioError(DioException error) {
    final status = error.response?.statusCode;
    if (status != null) {
      if (status == 401 || status == 403) {
        return LlmException(
          LlmErrorKind.auth,
          '密钥无效或没有权限（HTTP $status）',
          statusCode: status,
        );
      }
      if (status == 429) {
        return LlmException(
          LlmErrorKind.rateLimit,
          '请求太频繁（HTTP 429）',
          statusCode: status,
        );
      }
      if (status >= 500) {
        return LlmException(
          LlmErrorKind.server,
          '服务端出错（HTTP $status）',
          statusCode: status,
        );
      }
      // 400/422 表示请求被拒（正文常带 content/risk/policy/sensitive/违规/敏感
      // 等字样），451 同理；这些批的条目确定处理不了，重试后丢弃
      if (status == 400 || status == 422 || status == 451) {
        return LlmException(
          LlmErrorKind.refused,
          '服务商拒绝了这批内容（HTTP $status）',
          statusCode: status,
        );
      }
      // 其余 4xx（例如接口路径写错）不当作内容被拒，避免误删收集池
      return LlmException(
        LlmErrorKind.network,
        '接口地址或请求不正确（HTTP $status）',
        statusCode: status,
      );
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const LlmException(
          LlmErrorKind.timeout,
          '连接超时，可能需要配置代理',
        );
      case DioExceptionType.badCertificate:
        return const LlmException(
          LlmErrorKind.network,
          'HTTPS 证书校验失败，请检查接口地址或代理',
        );
      case DioExceptionType.cancel:
        return const LlmException(LlmErrorKind.network, '请求已取消');
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return const LlmException(LlmErrorKind.network, '网络错误，请检查网络或代理');
      case DioExceptionType.badResponse:
        return _parseError;
      default:
        return const LlmException(LlmErrorKind.network, '网络错误，请检查网络或代理');
    }
  }
}

/// 把错误类别转成给用户看的中文提示，句中不用句号
String llmErrorText(LlmErrorKind kind) => switch (kind) {
  LlmErrorKind.auth => '密钥无效',
  LlmErrorKind.rateLimit => '请求太频繁',
  LlmErrorKind.refused => '服务商拒绝了这批内容',
  LlmErrorKind.timeout => '连接超时，可能需要配置代理',
  LlmErrorKind.network => '网络错误',
  LlmErrorKind.server => '服务端出错',
  LlmErrorKind.parse => '返回内容无法解析',
  LlmErrorKind.budget => '已达今日用量上限',
};
