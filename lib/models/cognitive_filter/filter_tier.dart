/// 非专业模式下的档位，决定各内置类别的开关与阈值
enum FilterTier {
  basic('基础'),
  balanced('平衡'),
  strict('严格');

  const FilterTier(this.label);

  /// 默认档位
  static const FilterTier defaultTier = FilterTier.balanced;

  /// 界面显示的名称
  final String label;

  /// 档位到各内置类别 (enabled, threshold) 的映射
  ///
  /// 关闭的类别沿用出厂阈值，便于开启时直接使用
  Map<String, ({bool enabled, double threshold})> get builtinSettings =>
      switch (this) {
        FilterTier.basic => const {
          'attack': (enabled: true, threshold: 0.70),
          'discrim': (enabled: true, threshold: 0.60),
          'bait': (enabled: false, threshold: 0.70),
          'mock': (enabled: false, threshold: 0.85),
          'vulgar': (enabled: true, threshold: 0.80),
          'promo': (enabled: true, threshold: 0.75),
        },
        FilterTier.balanced => const {
          'attack': (enabled: true, threshold: 0.65),
          'discrim': (enabled: true, threshold: 0.50),
          'bait': (enabled: true, threshold: 0.70),
          'mock': (enabled: true, threshold: 0.85),
          'vulgar': (enabled: true, threshold: 0.70),
          'promo': (enabled: true, threshold: 0.50),
        },
        FilterTier.strict => const {
          'attack': (enabled: true, threshold: 0.50),
          'discrim': (enabled: true, threshold: 0.40),
          'bait': (enabled: true, threshold: 0.55),
          'mock': (enabled: true, threshold: 0.80),
          'vulgar': (enabled: true, threshold: 0.55),
          'promo': (enabled: true, threshold: 0.40),
        },
      };
}

/// 类别灵敏度，专业模式里给滑杆用的快捷档
enum FilterSensitivity {
  low('低', 0.85),
  mid('中', 0.70),
  high('高', 0.50);

  const FilterSensitivity(this.label, this.threshold);

  /// 界面显示的名称
  final String label;

  /// 对应的屏蔽阈值
  final double threshold;
}
