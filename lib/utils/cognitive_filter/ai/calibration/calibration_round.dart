import 'dart:convert';
import 'dart:math';

import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_models.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/llm_client.dart';
import 'package:PiliPlus/utils/cognitive_filter/raw_error.dart';

/// 一轮整理调用模型时的 system 提示
const String calibrationSystemPrompt =
    '你是内容分类助手。把用户给出的若干条网络短文本，按相同的内容类型归成几类。'
    '只输出 JSON，不要解释。';

/// 一轮整理调用模型时的 user 提示开头，后面逐行接“编号. 文本”
const String calibrationUserPromptHead =
    '下面是编号文本，请把属于同一类型的归在一起（例如同一种辱骂方式、同一种玩梗、'
    '同一种广告引流）。只有明显同类的才归在一起，没有同类的编号不要输出。'
    '尽量分得细一些：每类 3 到 10 条，宁可多分几类，也不要把不同类型混在一起；'
    '也不要让同一个话题或同一件事占满所有类别，尽量让各类覆盖不同的话题。'
    '每类给 名称（不超过 8 个字）、描述（一句话，说明这类内容的共同特点，语气中性）、'
    '成员编号。输出格式：[{"名称":"","描述":"","成员编号":[1,2,3]}]';

/// 一轮整理的结果
class RoundResult {
  const RoundResult({
    required this.questions,
    required this.usedIds,
    required this.droppedIds,
    this.abortedBy,
    this.abortMessage,
  });

  /// 这一轮归出来的题目
  final List<CalibrationQuestion> questions;

  /// 已成为题目成员的池条目 id，调用方应从池里删除
  final Set<String> usedIds;

  /// 确定处理不了、应从池里删除的条目 id
  final Set<String> droppedIds;

  /// 非空表示因网络/密钥/限流/服务端/超时/费用上限中止；用户点停止也会归入
  /// [LlmErrorKind.budget] 且消息为合成文案。中止前已出题的条目仍算用掉，
  /// 中止时当前批的条目留在池里
  final LlmErrorKind? abortedBy;

  /// 中止时给用户看的说明，可能是异常原文，也可能是“未填写 API Key”这类合成文案
  final String? abortMessage;
}

/// 从候选里取至多 [limit] 条，尽量来自不同来源
///
/// 先把每个来源内部打乱，再轮流从各来源各取一条（来源顺序也随机），
/// 这样一个来源再大也只会占到均摊的份额；没有来源的条目各算一个来源。
/// 最后整体打乱，免得分批时同一来源挤在同一批
List<PoolItem> _pickSpread(List<PoolItem> candidates, int limit, Random rng) {
  if (limit <= 0 || candidates.isEmpty) {
    return const <PoolItem>[];
  }
  final groups = <String, List<PoolItem>>{};
  for (final item in candidates) {
    final key = item.source.isEmpty ? '#${item.id}' : item.source;
    groups.putIfAbsent(key, () => <PoolItem>[]).add(item);
  }
  final lists = groups.values.toList()..shuffle(rng);
  for (final list in lists) {
    list.shuffle(rng);
  }
  final picked = <PoolItem>[];
  for (var round = 0; picked.length < limit; round++) {
    var any = false;
    for (final list in lists) {
      if (round < list.length) {
        picked.add(list[round]);
        any = true;
        if (picked.length >= limit) break;
      }
    }
    if (!any) break;
  }
  picked.shuffle(rng);
  return picked;
}

/// 跑一轮整理：过滤不该上传的内容，分批交给模型归类，攒出题目
///
/// [outputRetries] 是模型输出不合格（解析不了、被拒绝）时的重试次数，
/// [otherRetries] 是网络/超时/服务端/限流这类与输出无关问题的重试次数；
/// 总尝试次数均为 1 + 次数。
Future<RoundResult> runRound({
  required List<PoolItem> pool,
  required LlmChat chat,
  required bool Function(String text) isBlockedForUpload,
  Random? random,
  int maxItems = 150,
  int chunkSize = 40,
  int minClusterSize = 3,
  int maxQuestions = calibrationMaxQuestions,
  void Function(int done, int total)? onProgress,
  bool Function()? shouldStop,
  Duration retryDelay = const Duration(seconds: 2),
  int outputRetries = 1,
  int otherRetries = 2,
}) async {
  final droppedIds = <String>{};
  final candidates = <PoolItem>[];
  for (final item in pool) {
    if (isBlockedForUpload(item.text)) {
      droppedIds.add(item.id);
    } else {
      candidates.add(item);
    }
  }

  final rng = random ?? Random();
  final itemLimit = maxItems <= 0 ? 0 : maxItems;
  final selected = _pickSpread(candidates, itemLimit, rng);
  final size = chunkSize <= 0 ? 1 : chunkSize;
  final minSize = minClusterSize <= 0 ? 1 : minClusterSize;
  final questionLimit = maxQuestions <= 0 ? 0 : maxQuestions;
  // 重试次数由调用方按设置传入，总尝试次数 = 1 + 次数
  final maxOutputAttempts = outputRetries < 0 ? 1 : outputRetries + 1;
  final maxOtherAttempts = otherRetries < 0 ? 1 : otherRetries + 1;
  final chunks = <List<PoolItem>>[
    for (var start = 0; start < selected.length; start += size)
      selected.sublist(
        start,
        start + size < selected.length ? start + size : selected.length,
      ),
  ];

  final questions = <CalibrationQuestion>[];
  final total = chunks.length;
  LlmErrorKind? abortedBy;
  String? abortMessage;
  var processedChunks = 0;

  // 分好批就先报一次总数，界面不用等第一批完成才知道总批数
  onProgress?.call(0, total);

  for (var index = 0; index < chunks.length; index++) {
    if (questions.length >= questionLimit) {
      break;
    }
    // 每批开始前确认今日费用是否到上限；已到上限就停掉整轮，已得的题保留
    if (shouldStop?.call() ?? false) {
      const budgetError = LlmException(LlmErrorKind.budget, '已达今日费用上限');
      abortedBy = budgetError.kind;
      abortMessage = budgetError.message;
      break;
    }
    final chunk = chunks[index];
    final messages = <LlmMessage>[
      const LlmMessage(role: 'system', content: calibrationSystemPrompt),
      LlmMessage(role: 'user', content: _buildUserPrompt(chunk)),
    ];

    var abort = false;
    var batchFailed = false;
    // 失败按原因分开数：模型输出的问题（解析不了、被拒绝）重试也多半一样，
    // 默认只再试一次，免得白花钱；网络、超时、服务端、限流这类与输出无关的
    // 问题默认最多试三次，整理在后台跑，用户愿意等
    var outputFailures = 0;
    var otherFailures = 0;
    while (true) {
      try {
        final parsed = _parseReply(
          await chat(messages),
          chunk,
          minSize,
          questionLimit - questions.length,
        );
        questions.addAll(parsed);
        break;
      } catch (error) {
        final kind = error is LlmException ? error.kind : LlmErrorKind.network;
        if (kind == LlmErrorKind.auth || kind == LlmErrorKind.budget) {
          abortedBy = kind;
          abortMessage = llmErrorMessage(error);
          abort = true;
          break;
        }
        if (_isOutputProblem(kind)) {
          outputFailures++;
          if (outputFailures >= maxOutputAttempts) {
            batchFailed = true;
            break;
          }
        } else {
          otherFailures++;
          if (otherFailures >= maxOtherAttempts) {
            // 与模型输出无关，说明网络或服务有问题：停掉整轮，池里条目不动
            abortedBy = kind;
            abortMessage = llmErrorMessage(error);
            abort = true;
            break;
          }
          if (retryDelay > Duration.zero) {
            await Future<void>.delayed(retryDelay * otherFailures);
          }
        }
      }
    }

    if (batchFailed) {
      droppedIds.addAll(chunk.map((item) => item.id));
    }
    processedChunks++;
    onProgress?.call(processedChunks, total);
    if (abort) {
      break;
    }
  }

  return RoundResult(
    questions: questions,
    usedIds: <String>{
      for (final question in questions)
        for (final member in question.members) member.id,
    },
    droppedIds: droppedIds,
    abortedBy: abortedBy,
    abortMessage: abortMessage,
  );
}

/// 是不是模型输出本身的问题（解析不了或被拒绝）
bool _isOutputProblem(LlmErrorKind kind) =>
    kind == LlmErrorKind.parse || kind == LlmErrorKind.refused;

/// 取异常里给用户看的原始说明，非 [LlmException] 也脱敏并截断
String llmErrorMessage(Object error) {
  if (error is LlmException) {
    return error.message;
  }
  return truncateError(redactSecrets(error.toString()));
}

/// 拼出 user 提示：开头说明 + 逐行“编号. 文本”
String _buildUserPrompt(List<PoolItem> chunk) {
  final buffer = StringBuffer(calibrationUserPromptHead);
  for (var index = 0; index < chunk.length; index++) {
    buffer.write('\n');
    buffer.write(index + 1);
    buffer.write('. ');
    buffer.write(_promptText(chunk[index].text));
  }
  return buffer.toString();
}

/// 单条文本压成一行并截断 200 字
String _promptText(String text) {
  final flat = text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  return _clip(flat, 200);
}

/// 解析一批的返回，宽松接受围栏、数组或对象包裹
List<CalibrationQuestion> _parseReply(
  String raw,
  List<PoolItem> chunk,
  int minSize,
  int slots,
) {
  final clusters = _clustersFrom(raw);
  final assigned = <int>{};
  final questions = <CalibrationQuestion>[];

  for (final cluster in clusters) {
    if (questions.length >= slots) {
      break;
    }
    if (cluster is! Map) {
      continue;
    }
    final members = _memberIndexes(cluster, chunk.length, assigned);
    if (members.length < minSize) {
      // 人数不够的类丢弃，成员不算用掉，后面的类还能用
      continue;
    }
    final description = _clip(
      flattenText(_stringField(cluster, '描述', 'description')),
      60,
    );
    var name = _clip(flattenText(_stringField(cluster, '名称', 'name')), 12);
    if (name.isEmpty) {
      name = _clip(description, 8);
    }
    if (name.isEmpty) {
      name = '未命名';
    }
    questions.add(
      CalibrationQuestion(
        name: name,
        description: description,
        members: <PoolItem>[
          for (final member in members) chunk[member - 1],
        ],
      ),
    );
    assigned.addAll(members);
  }
  return questions;
}

/// 从模型输出里取类别数组：支持 ```json 围栏、顶层数组、对象里的第一个数组
List<dynamic> _clustersFrom(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*[ \t]*\r?\n?'), '');
  }
  final fenceEnd = text.indexOf('```');
  if (fenceEnd >= 0) {
    text = text.substring(0, fenceEnd);
  }
  text = text.trim();

  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const LlmException(LlmErrorKind.parse, '归类结果不是合法 JSON');
  }
  if (decoded is List) {
    return decoded;
  }
  if (decoded is Map) {
    for (final value in decoded.values) {
      if (value is List) {
        return value;
      }
    }
  }
  throw const LlmException(LlmErrorKind.parse, '归类结果里没有类别数组');
}

/// 取出本批范围内的成员编号，去重并排除已归入前面类的编号
List<int> _memberIndexes(
  Map<dynamic, dynamic> cluster,
  int count,
  Set<int> assigned,
) {
  final raw = cluster['成员编号'] ?? cluster['members'];
  if (raw is! List) {
    return const <int>[];
  }
  final seen = <int>{};
  final members = <int>[];
  for (final value in raw) {
    final index = _asIndex(value);
    if (index == null || index < 1 || index > count) {
      continue;
    }
    if (assigned.contains(index) || !seen.add(index)) {
      continue;
    }
    members.add(index);
  }
  members.sort();
  return members;
}

/// 成员编号只认整数，整数形式的 double（如 2.0）也接受
int? _asIndex(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    if (!value.isFinite) {
      return null;
    }
    return value == value.roundToDouble() ? value.toInt() : null;
  }
  return null;
}

String _stringField(
  Map<dynamic, dynamic> cluster,
  String primary,
  String fallback,
) {
  final value = cluster[primary] ?? cluster[fallback];
  return value is String ? value : '';
}

/// 按字符数截断，避免把表情符号的代理对切开
String _clip(String text, int max) {
  final runes = text.runes.toList(growable: false);
  if (runes.length <= max) {
    return text;
  }
  return String.fromCharCodes(runes.take(max));
}
