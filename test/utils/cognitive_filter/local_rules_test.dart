import 'package:PiliPlus/utils/cognitive_filter/local_rules.dart';
import 'package:flutter_test/flutter_test.dart';

const _templateSegment = '这是一条用于测试整段复制粘贴的合成弹幕内容';
const _funeralSegment = '请保持冷静并尽快联系殡仪馆处理后续相关事务';
const _syntheticSegment = '合成样例文本用于验证整段复制粘贴判断逻辑';
const _emojiSegment = '😀这是一条用于测试整段复制粘贴的合成内容';

void _expectHit(String rule, String text) {
  expect(
    LocalRules.hits(text),
    contains(rule),
    reason: '应命中 $rule：$text',
  );
}

void _expectClean(String text) {
  expect(
    LocalRules.hits(text),
    isEmpty,
    reason: '不应命中任何规则：$text',
  );
}

void main() {
  group('template_curse', () {
    test('命中“如果/父母/死亡 + 两个殡葬流程词”的模板', () {
      _expectHit(
        LocalRules.templateCurse,
        '如果我的父母死亡，请先联系殡仪馆并保持冷静。',
      );
      _expectHit(
        LocalRules.templateCurse,
        '若全家去世，请先联系殡仪馆处理遗体。',
      );
      _expectHit(
        LocalRules.templateCurse,
        '万一亲人离世，殡仪馆会安排火化。',
      );
    });

    test('只有单个“父母/死亡”或流程词不足两个时不命中', () {
      _expectClean('如果父母死亡，我很伤心。');
      _expectClean('父母死亡后，联系殡仪馆处理遗体。');
      _expectClean('如果父母身体健康，就一起吃饭。');
      _expectClean('假如家人还在，殡仪馆只是路过。');
    });
  });

  group('homophone_curse', () {
    test('命中六类谐音/变形咒骂的最小上下文', () {
      _expectHit(LocalRules.homophoneCurse, '亖冯');
      _expectHit(LocalRules.homophoneCurse, '同意作者浮木消失');
      _expectHit(LocalRules.homophoneCurse, '作者老冯升天了');
      _expectHit(LocalRules.homophoneCurse, '乐子私募了');
      _expectHit(LocalRules.homophoneCurse, '引战司马');
      _expectHit(LocalRules.homophoneCurse, '直接法死');
    });

    test('本义或普通词不命中', () {
      _expectClean('私募基金正常运作');
      _expectClean('司马光砸缸');
      _expectClean('老冯今天来上班');
      _expectClean('浮木漂在水面上');
      _expectClean('这是一段普通弹幕');
    });
  });

  group('promo_link', () {
    test('命中 URL、加群、扫码、加微信和复制弹幕话术', () {
      _expectHit(LocalRules.promoLink, 'https://example.com');
      _expectHit(LocalRules.promoLink, 'example.com!');
      _expectHit(LocalRules.promoLink, '加群一起玩');
      _expectHit(LocalRules.promoLink, '扫码进入');
      _expectHit(LocalRules.promoLink, '复制这段弹幕并发送');
      _expectHit(LocalRules.promoLink, '加微信了解');
    });

    test('普通“微信/链接/粉丝/QQ/扫把”不命中', () {
      _expectClean('微信只是一个软件');
      _expectClean('点击链接查看');
      _expectClean('粉丝很多');
      _expectClean('QQ音乐');
      _expectClean('扫把很干净');
      // Python 的 \b 是 Unicode 单词边界，“com中文”之间不是边界。
      _expectClean('example.com中文');
    });
  });

  group('symbol_wall', () {
    test('命中文末带文字的符号墙、方块墙和制表符墙', () {
      _expectHit(LocalRules.symbolWall, '测试！！！！！！！！');
      _expectHit(LocalRules.symbolWall, '■■■■■■■■');
      _expectHit(LocalRules.symbolWall, '⎛⎝≥⏝⏝≤⎛⎝');
      // 补充平面 emoji 必须按码点计数，不能按 UTF-16 码元误算比例。
      _expectHit(LocalRules.symbolWall, '😀😀😀😀😀😀😀😀');
    });

    test('防网暴/战术防御墙一律屏蔽', () {
      _expectHit(LocalRules.symbolWall, '防网暴！！！！！！！！');
      _expectHit(LocalRules.symbolWall, '战术防御墙！！！！');
      // Python 的 \s 含 U+001C，展开后的例外表正则仍应识别这个分隔符。
      _expectHit(LocalRules.symbolWall, '防\u001C网暴！！！！');
    });

    test('防剧透/防高能/打码保留，不按符号墙处理', () {
      _expectClean('防剧透！！！！！！！！');
      _expectClean('前方高能！！！！！！！！');
      _expectClean('打码保护画面！！！！');
    });

    test('纯问号、爱心和短颜文字不算墙', () {
      _expectClean('？？？？？？？？');
      _expectClean('♡♡♡♡♡♡♡♡');
      _expectClean('好听！(*¯︶¯*)');
    });

    test('普通中文弹幕不算墙', () {
      _expectClean('这是一段正常的弹幕文本');
    });

    test('按码点而不是 UTF-16 码元计算符号占比', () {
      // 8 个 emoji + 4 个汉字：按码点是 8/12 < 70%，按 UTF-16 会误算成 16/20。
      _expectClean('😀😀😀😀😀😀😀😀测试弹幕');
    });

    test('U+FEFF 不是 Python 空白，不能当作防网暴的分隔符', () {
      _expectClean('防\uFEFF网暴！！！！');
    });
  });

  group('digit_flood', () {
    test('命中重复数字、短周期数字和全角数字', () {
      _expectHit(LocalRules.digitFlood, '99999999');
      _expectHit(LocalRules.digitFlood, '4444 4444');
      _expectHit(LocalRules.digitFlood, '54545454');
      _expectHit(LocalRules.digitFlood, '233333333');
      _expectHit(LocalRules.digitFlood, '２３２３２３２３');
      // Python 的 \s 含 U+001C，Dart 的 \s 不含；移植后仍应去掉再判断。
      _expectHit(LocalRules.digitFlood, '9999\u001C9999');
    });

    test('纯 5/6/8 保留', () {
      _expectClean('88888888');
      _expectClean('66666666');
      _expectClean('55555555');
      _expectClean('8 8 8 8 8 8 8 8');
    });

    test('8 位日期、手机号和普通数字不命中', () {
      _expectClean('20240101');
      _expectClean('13800138000');
      _expectClean('1234567890');
      // Python 的 \s 不含 U+FEFF（Dart 的含），所以 BOM 不能被当成空白吞掉。
      _expectClean('9999\uFEFF9999');
    });
  });

  group('long_paste', () {
    test('命中同一段 >=20 字、重复 >=3 次的整段复制', () {
      _expectHit(
        LocalRules.longPaste,
        List<String>.filled(3, _templateSegment).join(),
      );
      _expectHit(
        LocalRules.longPaste,
        '前缀${List<String>.filled(3, _funeralSegment).join()}',
      );
      _expectHit(
        LocalRules.longPaste,
        List<String>.filled(4, _syntheticSegment).join(),
      );
      // 含补充平面 emoji 的 20 码点片段，切片和周期都必须按码点计算。
      _expectHit(
        LocalRules.longPaste,
        List<String>.filled(3, _emojiSegment).join(),
      );
    });

    test('短口号复读、纯 ASCII、保护词和正常长句不命中', () {
      _expectClean(List<String>.filled(20, '老师加油').join());
      _expectClean(List<String>.filled(20, 'kksk').join());
      _expectClean(
        '这是一段足够长的普通弹幕内容用来验证整段复制粘贴规则'
        '不会误伤正常表达也不会把正常讨论当成刷屏',
      );
      _expectClean(
        '${List<String>.filled(3, _templateSegment).join()}防剧透',
      );
      _expectClean(List<String>.filled(20, '好听').join());
    });
  });

  group('public api', () {
    test('ruleNames 保持原型固定顺序', () {
      expect(LocalRules.ruleNames, const <String>[
        'template_curse',
        'homophone_curse',
        'promo_link',
        'symbol_wall',
        'digit_flood',
        'long_paste',
      ]);
    });

    test('hits 返回全部命中并按固定顺序排列', () {
      expect(
        LocalRules.hits('www.！！！！！！！！！！'),
        const <String>['promo_link', 'symbol_wall'],
      );
    });

    test('空内容不命中', () {
      expect(LocalRules.hits(''), isEmpty);
    });

    test('verdict 返回是否屏蔽与首条命中规则名', () {
      final blocked = LocalRules.verdict('www.！！！！！！！！！！');
      expect(blocked.blocked, isTrue);
      expect(blocked.rule, LocalRules.promoLink);

      final clean = LocalRules.verdict('这是一段普通弹幕');
      expect(clean.blocked, isFalse);
      expect(clean.rule, '');
    });
  });
}
