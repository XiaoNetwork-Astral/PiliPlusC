/// 非专业模式下的档位，决定拦哪些内置类别
///
/// 所有档位共用同一个很高的阈值，AI 只拦十足把握的内容；档位越高，
/// 纳入的类别越多，而不是对同一类别拦得更狠
enum FilterTier {
  basic('基础'),
  balanced('平衡'),
  strict('严格');

  const FilterTier(this.label);

  /// 默认档位
  static const FilterTier defaultTier = FilterTier.basic;

  /// 界面显示的名称
  final String label;

  /// 屏蔽阈值：启用类别的概率之和达到它才屏蔽，三档相同
  ///
  /// 真实弹幕上 0.9 时误杀约 0.1%，再往下误拦的多是玩梗和讨论
  double get threshold => 0.90;

  /// 档位到各内置类别 (enabled, threshold) 的映射
  ///
  /// 所有内置类别共用档位阈值；关闭的类别沿用同一阈值，便于开启时直接使用
  Map<String, ({bool enabled, double threshold})> get builtinSettings {
    final enabled = switch (this) {
      FilterTier.basic => const {'attack', 'discrim', 'promo'},
      FilterTier.balanced => const {'attack', 'discrim', 'promo', 'vulgar'},
      FilterTier.strict => const {
        'attack',
        'discrim',
        'promo',
        'vulgar',
        'bait',
      },
    };
    return {
      for (final id in const [
        'attack',
        'discrim',
        'bait',
        'mock',
        'vulgar',
        'promo',
      ])
        id: (enabled: enabled.contains(id), threshold: threshold),
    };
  }
}
