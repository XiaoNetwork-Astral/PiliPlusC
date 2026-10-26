import 'package:PiliPlus/utils/cognitive_filter/ai/ai_whitelist_rules.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';

/// AI 屏蔽白名单的读写入口
///
/// 只影响 AI 屏蔽，规则屏蔽仍然照常生效；白名单随设置备份一起保存
class AiWhitelist {
  AiWhitelist._();

  static final AiWhitelist instance = AiWhitelist._();

  /// 任何改动都会自增，供编译缓存失效与界面刷新
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  AiWhitelistMatcher? _matcher;
  int _matcherVersion = -1;

  List<AiWhitelistEntry> get entries {
    try {
      return Pref.cfAiWhitelist;
    } catch (_) {
      return const <AiWhitelistEntry>[];
    }
  }

  /// 添加一条白名单，重复的忽略并返回 false
  bool add(AiWhitelistType type, String content) {
    final text = content.trim();
    if (text.isEmpty) return false;
    final current = entries;
    if (current.any((entry) => _isSame(entry, type, text))) return false;
    Pref.cfAiWhitelist = [
      ...current,
      AiWhitelistEntry(
        id: AiWhitelistEntry.nextId(),
        type: type,
        content: text,
        enabled: true,
      ),
    ];
    _bump();
    return true;
  }

  /// 把整段文字当关键词加入，去掉首尾空白，空文本返回 false
  bool addKeywordFromText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    return add(AiWhitelistType.keyword, trimmed);
  }

  /// 按 id 更新；条目不存在时忽略
  void update(AiWhitelistEntry entry) {
    final current = entries;
    final index = current.indexWhere((item) => item.id == entry.id);
    if (index < 0) return;
    final next = <AiWhitelistEntry>[...current];
    next[index] = entry;
    Pref.cfAiWhitelist = next;
    _bump();
  }

  void remove(String id) {
    final current = entries;
    final next = <AiWhitelistEntry>[
      for (final entry in current)
        if (entry.id != id) entry,
    ];
    if (next.length == current.length) return;
    Pref.cfAiWhitelist = next;
    _bump();
  }

  void setEnabled(String id, bool enabled) {
    final current = entries;
    final index = current.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    if (current[index].enabled == enabled) return;
    final next = <AiWhitelistEntry>[...current];
    next[index] = current[index].copyWith(enabled: enabled);
    Pref.cfAiWhitelist = next;
    _bump();
  }

  /// 文字是否命中启用中的白名单；编译结果按 [version] 缓存
  bool matches(String text) {
    try {
      final currentVersion = version.value;
      if (_matcher == null || _matcherVersion != currentVersion) {
        _matcher = AiWhitelistMatcher(entries);
        _matcherVersion = currentVersion;
      }
      return _matcher!.matches(text);
    } catch (_) {
      return false;
    }
  }

  bool _isSame(AiWhitelistEntry entry, AiWhitelistType type, String content) {
    if (entry.type != type) return false;
    if (type == AiWhitelistType.keyword) {
      return entry.content.toLowerCase() == content.toLowerCase();
    }
    return entry.content == content;
  }

  void _bump() {
    version.value = version.value + 1;
  }
}
