import 'package:PiliPlus/models/cognitive_filter/filter_category.dart';
import 'package:PiliPlus/models/cognitive_filter/filter_surface.dart';

const Set<FilterSurface> _allSurfaces = {
  FilterSurface.danmaku,
  FilterSurface.reply,
  FilterSurface.dynamic,
  FilterSurface.video,
  FilterSurface.live,
};

/// 内置类别，id 固定不变，存储里只记录对它们的覆盖
///
/// 出厂默认等于「基础」档：attack、discrim、vulgar、promo 开启且阈值为 0.70，
/// bait、mock 关闭，适用面均为四个全选。
const List<FilterCategory> builtinCategories = [
  FilterCategory(
    id: 'attack',
    name: '辱骂与诅咒',
    summary: '辱骂、人身攻击与诅咒',
    question: '它是否在辱骂、人身攻击、诅咒别人，或叫人去死？',
    trueCriteria:
        '针对某个或某些具体的人（观众、UP 主、选手、战队成员等）使用侮辱性称呼、辱骂、人身攻击、诅咒，或明确叫人去死、遭遇不幸；用谐音、缩写、表情等方式包装的同类攻击也算。',
    falseCriteria:
        '不针对具体人的粗口感叹（如“卧槽”“什么鬼”）、夸张情绪、游戏语境里的“杀”“打爆”“秒了”、无恶意的玩梗、对事不对人的正常批评，都算“否”。',
    threshold: FilterCategory.defaultThreshold,
    enabled: true,
    surfaces: _allSurfaces,
    builtin: true,
  ),
  FilterCategory(
    id: 'discrim',
    name: '歧视与污名化',
    summary: '针对群体的歧视与污名化',
    question: '它是否在歧视或污名化某个群体（性别、地域、民族、职业、学历等）？',
    trueCriteria:
        '基于性别、地域、民族、种族、职业、学历、外貌、身体状况等群体身份，对该群体进行歧视、污名化、贬低、标签化攻击，或把负面特征归因于整个群体。',
    falseCriteria:
        '不带群体贬损的普通陈述、仅针对具体行为的批评、不贬损他人的自嘲，以及不针对具体人的粗口感叹、夸张情绪、游戏语境里的“杀”“打爆”、无恶意的玩梗，都算“否”。',
    threshold: FilterCategory.defaultThreshold,
    enabled: true,
    surfaces: _allSurfaces,
    builtin: true,
  ),
  FilterCategory(
    id: 'bait',
    name: '引战拉踩',
    summary: '引战拉踩、挑动对立',
    question: '它是否在引战、拉踩、带节奏，或挑动不同群体（性别、地域、粉丝圈、赛区）之间的对立？',
    trueCriteria:
        '以挑动对立为目的，进行引战、拉踩、带节奏，或挑拨不同群体（性别、地域、民族、粉丝圈、赛区、主播之间）互相攻击；包括用反问、假设、比较等方式煽动站队。',
    falseCriteria:
        '正常讨论、观点表达、对比赛或选手的中性比较而不煽动对立，以及不针对具体人的粗口感叹、夸张情绪、游戏语境里的“杀”“打爆”、无恶意的玩梗，都算“否”。',
    threshold: FilterCategory.defaultThreshold,
    enabled: false,
    surfaces: _allSurfaces,
    builtin: true,
  ),
  FilterCategory(
    id: 'mock',
    name: '阴阳怪气',
    summary: '阴阳怪气、讥讽贬低',
    question: '它是否在讥讽、嘲弄或阴阳怪气地贬低某个观众、选手、战队、UP 主或官方？',
    trueCriteria:
        '用反讽、阴阳怪气、明褒暗贬、故意抬高再摔等方式，嘲弄或贬低某个观众、选手、战队、UP 主或官方，使其显得可笑、无能或活该。',
    falseCriteria:
        '真诚的赞美或正常批评、没有贬低对象的普通玩笑、无恶意的玩梗，以及不针对具体人的粗口感叹、夸张情绪、游戏语境里的“杀”“打爆”，都算“否”。',
    threshold: FilterCategory.defaultThreshold,
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
        '含有低俗、性暗示、性骚扰、露骨色情，或与性器官、性行为相关的不雅内容；包括用谐音、缩写、emoji 等方式表达的同类内容。',
    falseCriteria:
        '不含性意味的粗口感叹、普通玩笑、游戏术语、正常情感表达，以及不针对具体人的夸张情绪、游戏语境里的“杀”“打爆”、无恶意的玩梗，都算“否”。',
    threshold: FilterCategory.defaultThreshold,
    enabled: true,
    surfaces: _allSurfaces,
    builtin: true,
  ),
  FilterCategory(
    id: 'promo',
    name: '广告引流',
    summary: '广告引流、求关注拉群',
    question: '它是否在打广告、引流、求关注或拉群？',
    trueCriteria:
        '在打广告、引流到站外平台、求关注/点赞/投币/转发、拉群、卖课卖货，或发布明显的推广口令、二维码、联系方式。',
    falseCriteria:
        '正常提及视频、主播或商品，玩梗式地说“下次一定”“已三连”，以及没有推广意图的普通互动、不针对具体人的粗口感叹、夸张情绪、无恶意的玩梗，都算“否”。',
    threshold: FilterCategory.defaultThreshold,
    enabled: true,
    surfaces: _allSurfaces,
    builtin: true,
  ),
];
