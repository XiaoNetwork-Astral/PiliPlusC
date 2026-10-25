import 'package:PiliPlus/utils/cognitive_filter/ai/judge_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeJudgeText', () {
    test('去掉首尾空白', () {
      expect(normalizeJudgeText('  前排  '), '前排');
      expect(normalizeJudgeText('\t你好\n'), '你好');
    });

    test('同一字符连续 4 次以上压缩到 3 次', () {
      expect(normalizeJudgeText('啊啊啊啊'), '啊啊啊');
      expect(normalizeJudgeText('aaaaa'), 'aaa');
      expect(normalizeJudgeText('aaabbbb'), 'aaabbb');
      expect(normalizeJudgeText('abbbbb'), 'abbb');
    });

    test('不足 4 次的连续字符保持原样', () {
      expect(normalizeJudgeText('aaa'), 'aaa');
      expect(normalizeJudgeText('abbb'), 'abbb');
    });

    test('不同字符不会合并，按码点处理代理对', () {
      expect(normalizeJudgeText('aabbcc'), 'aabbcc');
      expect(normalizeJudgeText('😀😀😀😀'), '😀😀😀');
      expect(normalizeJudgeText('😀😀😀'), '😀😀😀');
    });

    test('空串与纯空白', () {
      expect(normalizeJudgeText(''), '');
      expect(normalizeJudgeText('   '), '');
    });
  });

  group('isTooShortToJudge', () {
    test('两个字符及以内算太短', () {
      expect(isTooShortToJudge('前排'), isTrue);
      expect(isTooShortToJudge('你好'), isTrue);
      expect(isTooShortToJudge('😀😀'), isTrue);
      expect(isTooShortToJudge(''), isTrue);
    });

    test('去掉空白后判断', () {
      expect(isTooShortToJudge(' 前 排 '), isTrue);
      expect(isTooShortToJudge('你 好'), isTrue);
      expect(isTooShortToJudge('你  好  呀'), isFalse);
    });

    test('去掉标点与引号后判断', () {
      expect(isTooShortToJudge('。。。'), isTrue);
      expect(isTooShortToJudge('！？!?,.~～…·'), isTrue);
      expect(isTooShortToJudge('“你好”'), isTrue);
      expect(isTooShortToJudge('`abc`'), isFalse);
      expect(isTooShortToJudge('a。b'), isTrue);
      expect(isTooShortToJudge('你，好！'), isTrue);
    });

    test('连续 3 次以上压缩到 2 次后判断', () {
      expect(isTooShortToJudge('好好好'), isTrue);
      expect(isTooShortToJudge('啊啊啊啊'), isTrue);
      expect(isTooShortToJudge('哈哈哈'), isTrue);
      expect(isTooShortToJudge('哈哈哈呀'), isFalse);
    });

    test('三个不同字符不算太短', () {
      expect(isTooShortToJudge('abc'), isFalse);
      expect(isTooShortToJudge('你好呀'), isFalse);
    });
  });
}
