import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';

const Set<FilterSurface> _allSurfaces = {
  FilterSurface.danmaku,
  FilterSurface.reply,
  FilterSurface.dynamic,
  FilterSurface.video,
  FilterSurface.live,
};

/// 内置类别共用的出厂屏蔽门槛：只拦十足把握的内容，拿不准的一律放行
const double kDefaultBlockThreshold = 0.90;

/// 内置类别，id 固定不变，存储里只记录对它们的覆盖
///
/// 出厂默认只开 attack、discrim、promo，其余关闭，适用面均为五个全选；
/// 内置类别共用一个总阈值（出厂见 [kDefaultBlockThreshold]），
/// 这里的 threshold 只是占位。
const List<FilterCategory> builtinCategories = [
  FilterCategory(
    id: 'attack',
    name: '辱骂与诅咒',
    summary: '辱骂、人身攻击与诅咒',
    question: '它是否在辱骂、人身攻击或诅咒某个人？',
    trueCriteria:
        '对具体的个人使用侮辱性称呼、辱骂、人身攻击、诅咒，或叫人去死、遭遇不幸；用谐音、缩写、表情等方式包装的同类攻击也算。',
    falseCriteria:
        '不针对具体对象的口头禅和感叹、夸张的情绪表达、无恶意的玩笑和玩梗、对事不对人的批评、对作品或游戏里暴力情节的描述，都算“否”。',
    threshold: 0.55,
    enabled: true,
    surfaces: _allSurfaces,
    builtin: true,
  ),
  FilterCategory(
    id: 'discrim',
    name: '歧视与污名化',
    summary: '针对群体的歧视与污名化',
    question: '它是否在歧视或污名化某个群体？',
    trueCriteria:
        '基于性别、地域、民族、种族、职业、学历、外貌、身体状况等群体身份，对该群体进行歧视、贬低、污名化或标签化攻击，或把负面特征归因于整个群体。',
    falseCriteria:
        '不带群体贬损的普通陈述、只针对具体行为的批评、不贬损他人的自嘲、无恶意的玩笑和玩梗，都算“否”。',
    threshold: 0.55,
    enabled: true,
    surfaces: _allSurfaces,
    builtin: true,
  ),
  FilterCategory(
    id: 'bait',
    name: '引战拉踩',
    summary: '引战拉踩、挑动对立',
    question: '它是否在引战、拉踩或挑动不同群体之间的对立？',
    trueCriteria:
        '以挑动对立为目的，进行引战、拉踩、带节奏，或挑拨不同群体（性别、地域、民族、粉丝圈等）互相攻击；包括用反问、假设、比较等方式煽动站队。',
    falseCriteria:
        '正常讨论、观点表达、不煽动对立的中性比较、无恶意的玩笑和玩梗，都算“否”。',
    threshold: 0.55,
    enabled: false,
    surfaces: _allSurfaces,
    builtin: true,
  ),
  FilterCategory(
    id: 'mock',
    name: '阴阳怪气',
    summary: '阴阳怪气、讥讽贬低',
    question: '它是否在用反讽或阴阳怪气的方式嘲弄、贬低别人？',
    trueCriteria:
        '用反话、阴阳怪气、明褒暗贬、故意抬高再贬低等方式嘲弄或贬低他人，使其显得可笑、无能或活该。',
    falseCriteria:
        '真诚的赞美或正常批评、没有贬低对象的玩笑、不贬损他人的自嘲、无恶意的玩梗，都算“否”。',
    threshold: 0.55,
    enabled: false,
    surfaces: _allSurfaces,
    builtin: true,
  ),
  FilterCategory(
    id: 'vulgar',
    name: '低俗与性暗示',
    summary: '低俗、性暗示与骚扰',
    question: '它是否含有低俗、性暗示或骚扰内容？',
    trueCriteria:
        '含有低俗、性暗示、性骚扰、露骨色情，或与性器官、性行为相关的不雅内容；包括用谐音、缩写、表情等方式表达的同类内容。',
    falseCriteria:
        '不含性意味的粗口感叹、普通玩笑、专业或游戏术语、正常的情感表达，都算“否”。',
    threshold: 0.55,
    enabled: false,
    surfaces: _allSurfaces,
    builtin: true,
  ),
  FilterCategory(
    id: 'promo',
    name: '广告引流',
    summary: '广告、站外引流与卖课卖货',
    question: '它是否在推销商品或服务，或把人引到站外（加群、加微信、扫码、点链接）？',
    trueCriteria:
        '推销商品或服务、卖课卖货、代练代刷，发布站外联系方式（QQ、微信、群号、二维码）或外链，或明显的推广口令，目的是把人引流到站外或让人付费。',
    falseCriteria:
        'UP 主或作者在自己的视频、动态、评论里求点赞、投币、三连、关注、转发，征集想法或建议，预告更新，提醒看简介或评论区，都算“否”；玩梗式地说“下次一定”“已三连”，正常提及视频、主播或商品，没有推广意图的普通互动、不针对具体人的粗口感叹、夸张情绪、无恶意的玩梗，也都算“否”。',
    threshold: 0.55,
    enabled: true,
    surfaces: _allSurfaces,
    builtin: true,
  ),
];
