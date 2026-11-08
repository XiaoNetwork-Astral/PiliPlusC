/// 整理接口的 API 格式
enum LlmApiFormat {
  /// OpenAI 兼容的 chat/completions
  openai('OpenAI 兼容'),

  /// Anthropic Messages
  anthropic('Anthropic');

  const LlmApiFormat(this.label);

  final String label;
}

/// 判定接口的提供商
enum JudgeProvider {
  typesafe(
    'TypeSafe 官方',
    'https://api.typesafe.ai/v1/systemone',
    'jev-latest',
  ),
  bailian('阿里百炼', null, 'decision-model-preview'),
  custom('自定义接口', null, null);

  const JudgeProvider(this.label, this.baseUrl, this.model);

  final String label;

  /// 预设地址；阿里百炼要按业务空间拼，自定义由用户填写
  final String? baseUrl;

  /// 预设模型；自定义时沿用用户当前填写的模型
  final String? model;

  /// 阿里百炼按业务空间拼出的北京地址
  static String bailianBaseUrl(String workspaceId) {
    final id = workspaceId.trim();
    return 'https://${id}.cn-beijing.maas.aliyuncs.com'
        '/compatible-mode/v1/systemone';
  }

  /// 从阿里百炼地址里取业务空间 ID，不是北京地址时返回 null
  static String? bailianWorkspaceId(String baseUrl) {
    final host = Uri.tryParse(baseUrl.trim())?.host.toLowerCase() ?? '';
    const suffix = '.cn-beijing.maas.aliyuncs.com';
    if (!host.endsWith(suffix)) {
      return null;
    }
    final id = host.substring(0, host.length - suffix.length);
    return id.isEmpty ? null : id;
  }
}

/// 整理接口的提供商
enum OrganizeProvider {
  deepseek(
    'DeepSeek',
    'https://api.deepseek.com',
    'deepseek-flash',
    LlmApiFormat.openai,
  ),
  openai(
    'OpenAI',
    'https://api.openai.com/v1',
    'gpt-6-luna',
    LlmApiFormat.openai,
  ),
  anthropic(
    'Anthropic',
    'https://api.anthropic.com',
    'claude-haiku-5-5',
    LlmApiFormat.anthropic,
  ),
  custom('自定义接口', null, null, null);

  const OrganizeProvider(this.label, this.baseUrl, this.model, this.format);

  final String label;

  /// 预设地址；自定义由用户填写
  final String? baseUrl;

  /// 预设模型；自定义时沿用用户当前填写的模型
  final String? model;

  /// 预设格式；自定义时由用户在弹窗里选
  final LlmApiFormat? format;
}

/// 一条提示消息，只保留构造请求需要的角色与正文
typedef LlmPromptMessage = ({String role, String content});

String _hostOf(String url) {
  return Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
}

/// 判断主机是否等于某个域名或是它的子域，避免 `eviltypesafe.ai` 这类误判
bool _hostIn(String host, String domain) {
  return host == domain || host.endsWith('.$domain');
}

/// 判定接口地址对应的提供商
JudgeProvider judgeProviderForUrl(String baseUrl) {
  final host = _hostOf(baseUrl);
  if (_hostIn(host, 'typesafe.ai')) {
    return JudgeProvider.typesafe;
  }
  if (_hostIn(host, 'maas.aliyuncs.com')) {
    return JudgeProvider.bailian;
  }
  return JudgeProvider.custom;
}

/// 整理接口地址对应的提供商
OrganizeProvider organizeProviderForUrl(String baseUrl) {
  final host = _hostOf(baseUrl);
  if (_hostIn(host, 'deepseek.com')) {
    return OrganizeProvider.deepseek;
  }
  if (_hostIn(host, 'openai.com')) {
    return OrganizeProvider.openai;
  }
  if (_hostIn(host, 'anthropic.com')) {
    return OrganizeProvider.anthropic;
  }
  return OrganizeProvider.custom;
}

/// 是否为 DeepSeek 官方主机；思考参数只对这个主机发
bool isDeepSeekHost(String baseUrl) {
  return _hostIn(_hostOf(baseUrl), 'deepseek.com');
}

/// 是否为阿里百炼的判定接口主机
bool isBailianJudgeHost(String baseUrl) {
  return _hostIn(_hostOf(baseUrl), 'maas.aliyuncs.com');
}

/// 判定接口单次请求的题数上限；阿里百炼限制 16 题，其它地址返回 null
/// 表示沿用默认上限
int? judgeQuestionLimitForUrl(String baseUrl) {
  return isBailianJudgeHost(baseUrl) ? 16 : null;
}

/// 接口根地址是否形如 `http(s)://host`
bool isValidApiBaseUrl(String baseUrl) {
  final uri = Uri.tryParse(baseUrl.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// 拼出聊天接口地址
///
/// OpenAI 兼容格式固定追加 `/chat/completions`；Anthropic 格式追加
/// `/v1/messages`，根地址已经以 `/v1` 结尾时只追加 `/messages`。
String buildChatUrl(String baseUrl, LlmApiFormat format) {
  final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  return switch (format) {
    LlmApiFormat.openai => '$base/chat/completions',
    LlmApiFormat.anthropic => base.endsWith('/v1')
        ? '$base/messages'
        : '$base/v1/messages',
  };
}

/// 两种格式的请求头；Anthropic 用 x-api-key，不发 Authorization
Map<String, String> llmRequestHeaders({
  required LlmApiFormat format,
  required String apiKey,
  required bool streaming,
}) {
  final accept = streaming ? 'text/event-stream' : 'application/json';
  return switch (format) {
    LlmApiFormat.openai => <String, String>{
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'Accept': accept,
    },
    LlmApiFormat.anthropic => <String, String>{
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'Content-Type': 'application/json',
      'Accept': accept,
    },
  };
}

/// 构造一次聊天请求的请求体
///
/// OpenAI 兼容格式保持原有字段；Anthropic 格式把 system 消息抽到顶层，
/// 其余消息按轮次发送，并固定带 `max_tokens`。Anthropic 不发 temperature、
/// thinking、response_format 这些字段。
Map<String, dynamic> buildLlmRequestBody({
  required LlmApiFormat format,
  required String model,
  required List<LlmPromptMessage> messages,
  double temperature = 0.2,
  bool streaming = false,
  bool jsonMode = true,
  bool think = true,
  bool deepSeek = false,
  int? maxTokens,
}) {
  if (format == LlmApiFormat.anthropic) {
    final system = StringBuffer();
    final turns = <Map<String, dynamic>>[];
    for (final message in messages) {
      if (message.role == 'system') {
        if (message.content.isEmpty) {
          continue;
        }
        if (system.isNotEmpty) {
          system.write('\n\n');
        }
        system.write(message.content);
      } else {
        turns.add(<String, dynamic>{
          'role': message.role,
          'content': message.content,
        });
      }
    }
    return <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens ?? 32000,
      if (system.isNotEmpty) 'system': system.toString(),
      'messages': turns,
      'stream': streaming,
    };
  }

  final body = <String, dynamic>{
    'model': model,
    'messages': <Map<String, dynamic>>[
      for (final message in messages)
        <String, dynamic>{
          'role': message.role,
          'content': message.content,
        },
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
  if (deepSeek) {
    if (think) {
      body['thinking'] = const <String, dynamic>{'type': 'enabled'};
      body['reasoning_effort'] = 'high';
    } else {
      body['thinking'] = const <String, dynamic>{'type': 'disabled'};
    }
  }
  if (jsonMode && !(deepSeek && think)) {
    body['response_format'] = const <String, dynamic>{
      'type': 'json_object',
    };
  }
  if (maxTokens != null) {
    body['max_tokens'] = maxTokens;
  }
  return body;
}
