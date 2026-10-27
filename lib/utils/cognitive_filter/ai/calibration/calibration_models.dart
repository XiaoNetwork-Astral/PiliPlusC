/// 校准向导收集池里的一条内容
///
/// [score] 是收集时 AI 给出的屏蔽得分（启用类别概率之和），向导调门槛时用它
class PoolItem {
  const PoolItem({
    required this.id,
    required this.text,
    required this.surface,
    required this.score,
    required this.time,
    this.category = '',
    this.categoryId = '',
    this.source = '',
  });

  factory PoolItem.fromJson(Map<String, dynamic> json) => PoolItem(
    id: json['id'] as String,
    text: json['text'] as String,
    surface: json['surface'] as String,
    score: (json['score'] as num).toDouble(),
    time: json['time'] as int,
    category: json['category'] is String ? json['category'] as String : '',
    categoryId: json['categoryId'] is String ? json['categoryId'] as String : '',
    source: json['source'] is String ? json['source'] as String : '',
  );

  /// 池内唯一编号
  final String id;

  /// 原文
  final String text;

  /// 适用面的中文名
  final String surface;

  /// 收集时的屏蔽得分，0 到 1
  final double score;

  /// 收集时间，毫秒时间戳
  final int time;

  /// 收集时 AI 判定的类别名，没有则为空
  final String category;

  /// 收集时得分最高的内置类别 id，校准时据此归到各类别，没有则为空
  final String categoryId;

  /// 内容来源（所在视频标题之类），用来限制同一来源占满收集池，没有则为空
  final String source;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'surface': surface,
    'score': score,
    'time': time,
    if (category.isNotEmpty) 'category': category,
    if (categoryId.isNotEmpty) 'categoryId': categoryId,
    if (source.isNotEmpty) 'source': source,
  };
}

/// 用户对一道题的回答
enum CalibrationAnswer {
  /// 该拦
  block,

  /// 不该拦
  keep,

  /// 拿不准，不参与调门槛
  skip,
}

/// LLM 把一批内容归成的一类，也就是向导里的一道题
class CalibrationQuestion {
  const CalibrationQuestion({
    required this.name,
    required this.description,
    required this.members,
  });

  factory CalibrationQuestion.fromJson(Map<String, dynamic> json) =>
      CalibrationQuestion(
        name: json['name'] as String,
        description: json['description'] as String,
        members: <PoolItem>[
          for (final value in json['members'] as List)
            PoolItem.fromJson(Map<String, dynamic>.from(value as Map)),
        ],
      );

  /// 类别名称，几个字
  final String name;

  /// 一句话描述这类内容
  final String description;

  /// 属于这一类的池内条目，至少 3 条
  final List<PoolItem> members;

  /// 稳定唯一的编号，成员编号排序后拼接，答完后据此从题库精确删除
  String get id {
    final ids = <String>[for (final member in members) member.id]..sort();
    return ids.join('_');
  }

  /// 展示给用户看的一条代表：得分居中的成员，回答会应用到整类
  PoolItem get representative {
    final sorted = members.toList()..sort((a, b) => a.score.compareTo(b.score));
    return sorted[sorted.length ~/ 2];
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'members': <dynamic>[
      for (final member in members) member.toJson(),
    ],
  };
}

/// 去掉首尾空白并把连续空白折叠成一个空格
String flattenText(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// 一轮整理至少要凑出这么多道题才拿来答，不够就保留内容、不出题
const int calibrationMinQuestions = 10;

/// 一轮整理最多出这么多道题
const int calibrationMaxQuestions = 20;
