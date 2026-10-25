/// 非专业模式下的档位，决定各内置类别的开关与屏蔽阈值
enum FilterTier {
  basic('基础'),
  balanced('平衡'),
  strict('严格');

  const FilterTier(this.label);

  /// 默认档位
  static const FilterTier defaultTier = FilterTier.balanced;

  /// 界面显示的名称
  final String label;

  /// 该档位的屏蔽阈值：启用类别的概率之和达到它才屏蔽
  double get threshold => switch (this) {
    FilterTier.basic => 0.55,
    FilterTier.balanced => 0.55,
    FilterTier.strict => 0.75,
  };

  /// 档位到各内置类别 (enabled, threshold) 的映射
  ///
  /// 所有内置类别共用档位阈值；关闭的类别沿用同一阈值，便于开启时直接使用
  Map<String, ({bool enabled, double threshold})> get builtinSettings {
    final enabled = switch (this) {
      FilterTier.basic => const {'attack', 'discrim', 'vulgar', 'promo'},
      FilterTier.balanced => const {
        'attack',
        'discrim',
        'vulgar',
        'promo',
        'bait',
      },
      FilterTier.strict => const {
        'attack',
        'discrim',
        'vulgar',
        'promo',
        'bait',
        'mock',
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
