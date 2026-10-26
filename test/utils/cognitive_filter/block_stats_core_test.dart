import 'package:PiliPlus/utils/cognitive_filter/block_stats_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BlockStatsCore', () {
    late DateTime now;
    late int storedCount;
    late String storedSince;
    late int saves;
    late int savedCount;
    late String savedSince;

    BlockStatsCore build() {
      return BlockStatsCore(
        loadCount: () => storedCount,
        loadSince: () => storedSince,
        save: (count, since) {
          saves++;
          savedCount = count;
          savedSince = since;
          storedCount = count;
          storedSince = since;
        },
        now: () => now,
      );
    }

    setUp(() {
      now = DateTime(2024, 5, 6, 12, 30);
      storedCount = 0;
      storedSince = '';
      saves = 0;
      savedCount = -1;
      savedSince = '<none>';
    });

    test('初始读取已有累计，未改动时 flush 返回 false', () {
      storedCount = 12;
      storedSince = '2024-05-01';
      final stats = build();

      expect(stats.total, 12);
      expect(stats.days, 6);
      expect(stats.flushIfDirty(), isFalse);
      expect(saves, 0);
    });

    test('首次 add 记录起始日期并累计', () {
      final stats = build();

      stats.add(2);

      expect(stats.total, 2);
      expect(stats.days, 1);
      expect(saves, 0);
      expect(stats.flushIfDirty(), isTrue);
      expect(saves, 1);
      expect(savedCount, 2);
      expect(savedSince, '2024-05-06');
      expect(storedSince, '2024-05-06');
      expect(stats.flushIfDirty(), isFalse);
      expect(saves, 1);
    });

    test('已有起始日期时 add 不覆盖它', () {
      storedCount = 10;
      storedSince = '2024-05-01';
      final stats = build();

      stats.add(3);

      expect(stats.total, 13);
      expect(stats.days, 6);
      expect(stats.flushIfDirty(), isTrue);
      expect(savedCount, 13);
      expect(savedSince, '2024-05-01');
    });

    test('n≤0 忽略，不记起始日期也不弄脏', () {
      final stats = build();

      stats.add(0);
      stats.add(-5);

      expect(stats.total, 0);
      expect(stats.days, 0);
      expect(saves, 0);
      expect(stats.flushIfDirty(), isFalse);
      expect(storedSince, '');
    });

    test('跨天天数按本地日期计算，同一天为 1', () {
      storedSince = '2024-05-06';
      final stats = build();

      expect(stats.days, 1);
      now = DateTime(2024, 5, 7);
      expect(stats.days, 2);
      now = DateTime(2024, 6, 5, 23, 59);
      expect(stats.days, 31);
      now = DateTime(2025, 5, 6, 0, 1);
      expect(stats.days, 366);
    });

    test('跨年与闰日的天数', () {
      storedSince = '2023-12-31';
      now = DateTime(2024, 1, 1, 8);
      expect(build().days, 2);

      storedSince = '2024-02-28';
      now = DateTime(2024, 3, 1, 8);
      expect(build().days, 3);
    });

    test('脏标记合并多次 add，flushIfDirty 只落盘一次', () {
      final stats = build();

      stats.add(2);
      stats.add(3);

      expect(saves, 0);
      expect(stats.total, 5);
      expect(stats.flushIfDirty(), isTrue);
      expect(saves, 1);
      expect(savedCount, 5);
      expect(savedSince, '2024-05-06');
      expect(stats.flushIfDirty(), isFalse);
      expect(saves, 1);

      stats.add(4);
      expect(stats.total, 9);
      expect(stats.flushIfDirty(), isTrue);
      expect(saves, 2);
      expect(savedCount, 9);
    });

    test('reset 清零、清空起始日期并立即保存', () {
      storedCount = 5;
      storedSince = '2024-05-01';
      final stats = build();

      stats.add(2);
      stats.reset();

      expect(stats.total, 0);
      expect(stats.days, 0);
      expect(saves, 1);
      expect(savedCount, 0);
      expect(savedSince, '');
      expect(storedCount, 0);
      expect(storedSince, '');
      expect(stats.flushIfDirty(), isFalse);
      expect(saves, 1);
    });

    test('reset 不依赖是否读取过旧数据', () {
      final stats = build();

      stats.reset();

      expect(saves, 1);
      expect(savedCount, 0);
      expect(savedSince, '');
      expect(stats.total, 0);
    });

    test('坏日期或未来日期按 1 天处理', () {
      for (final since in <String>[
        'not-a-date',
        '2024-02-30',
        '2024-13-01',
        '2024-5-6',
        '0000-00-00',
        '2999-01-01',
      ]) {
        storedSince = since;
        expect(build().days, 1, reason: since);
      }
    });

    test('没有起始日期时天数为 0', () {
      storedCount = 8;
      expect(build().days, 0);
    });
  });
}
