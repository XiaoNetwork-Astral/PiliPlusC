import 'dart:convert';
import 'dart:math';

import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/calibration_models.dart';
import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/llm_client.dart';

/// 一轮整理调用模型时的 system 提示
const String calibrationSystemPrompt =
    '你是内容分类助手。把用户给出的若干条网络短文本，按相同的内容类型归成几类。'
    '只输出 JSON，不要解释。';

/// 一轮整理调用模型时的 user 提示开头，后面逐行接“编号. 文本”
const String calibrationUserPromptHead =
    '下面是编号文本，请把属于同一类型的归在一起（例如同一种辱骂方式、同一种玩梗、'
    '同一种广告引流）。只有明显同类的才归在一起，没有同类的编号不要输出。'
    '每类给 名称（不超过 8 个字）、描述（一句话，说明这类内容的共同特点，语气中性）、'
    '成员编号。输出格式：[{"名称":"","描述":"","成员编号":[1,2,3]}]';

/// 一轮整理的结果
class RoundResult {
  const RoundResult({
    required this.questions,
    required this.usedIds,
    required this.droppedIds,
    required this.refusedChunks,
    this.abortedBy,
    required this.processedChunks,
  });

  /// 这一轮归出来的题目
  final List<CalibrationQuestion> questions;

  /// 已成为题目成员的池条目 id，调用方应从池里删除
  final Set<String> usedIds;

  /// 确定处理不了、应从池里删除的条目 id
  final Set<String> droppedIds;

  /// 因服务商拒绝或返回无法解析而丢弃的批数
  final int refusedChunks;

  /// 非空表示因网络/密钥/限流/服务端/超时/用量上限中止，池里条目保持不动
  final LlmErrorKind? abortedBy;

  /// 实际处理过的批数
  final int processedChunks;
}

/// 跑一轮整理：过滤不该上传的内容，分批交给模型归类，攒出题目
Future<RoundResult> runRound({
  required List<PoolItem> pool,
  required LlmChat chat,
  required bool Function(String text) isBlockedForUpload,
  Random? random,
  int maxItems = 150,
  int chunkSize = 40,
  int minClusterSize = 3,
  int maxQuestions = 20,
  void Function(int done, int total)? onProgress,
  bool Function()? shouldStop,
  Duration retryDelay = const Duration(seconds: 2),
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
  candidates.shuffle(rng);
  final itemLimit = maxItems <= 0 ? 0 : maxItems;
  final selected = candidates.take(itemLimit).toList(growable: false);
  final size = chunkSize <= 0 ? 1 : chunkSize;
  final minSize = minClusterSize <= 0 ? 1 : minClusterSize;
  final questionLimit = maxQuestions <= 0 ? 0 : maxQuestions;
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
  var refusedChunks = 0;
  var processedChunks = 0;

  for (var index = 0; index < chunks.length; index++) {
    if (questions.length >= questionLimit) {
      break;
    }
    // 每批开始前确认今日用量额度；已到上限就停掉整轮，已得的题保留
    if (shouldStop?.call() ?? false) {
      abortedBy = LlmErrorKind.budget;
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
    // 再试一次就够，免得白花钱；网络、超时、服务端、限流这类与输出无关的问题
    // 整理在后台跑，用户愿意等，最多试三次
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
          abort = true;
          break;
        }
        if (_isOutputProblem(kind)) {
          outputFailures++;
          if (outputFailures >= _maxOutputAttempts) {
            batchFailed = true;
            break;
          }
        } else {
          otherFailures++;
          if (otherFailures >= _maxOtherAttempts) {
            // 与模型输出无关，说明网络或服务有问题：停掉整轮，池里条目不动
            abortedBy = kind;
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
      refusedChunks++;
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
    refusedChunks: refusedChunks,
    abortedBy: abortedBy,
    processedChunks: processedChunks,
  );
}

/// 模型输出问题：同一批最多发送的次数
const int _maxOutputAttempts = 2;

/// 与模型输出无关的问题：同一批最多发送的次数
const int _maxOtherAttempts = 3;

/// 是不是模型输出本身的问题（解析不了或被拒绝）
bool _isOutputProblem(LlmErrorKind kind) =>
    kind == LlmErrorKind.parse || kind == LlmErrorKind.refused;

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
      _clean(_stringField(cluster, '描述', 'description')),
      60,
    );
    var name = _clip(_clean(_stringField(cluster, '名称', 'name')), 12);
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

/// 空白压成单个空格并去掉首尾空白
String _clean(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// 按字符数截断，避免把表情符号的代理对切开
String _clip(String text, int max) {
  final runes = text.runes.toList(growable: false);
  if (runes.length <= max) {
    return text;
  }
  return String.fromCharCodes(runes.take(max));
}
