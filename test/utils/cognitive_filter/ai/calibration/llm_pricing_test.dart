import 'package:PiliPlus/utils/cognitive_filter/ai/calibration/llm_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('零用量不花钱', () {
    expect(llmCostCny(0, 0), 0.0);
  });

  test('一百万输入 token 按 2 元计', () {
    expect(llmCostCny(1000000, 0), 2.0);
  });

  test('一百万输出 token 按 8 元计', () {
    expect(llmCostCny(0, 1000000), 8.0);
  });

  test('输入与输出分别按各自单价相加', () {
    expect(llmCostCny(1000000, 500000), 6.0);
  });

  test('小用量按比例折算', () {
    // 1000 输入 = 0.002 元，2000 输出 = 0.016 元
    expect(llmCostCny(1000, 2000), closeTo(0.018, 1e-12));
  });

  test('负数按 0 计，不会算出负费用', () {
    expect(llmCostCny(-10, -20), 0.0);
    expect(llmCostCny(-10, 1000000), 8.0);
  });

  test('价格常量取 DeepSeek 高峰时段人民币价', () {
    expect(llmInputPriceCnyPerMillion, 2.0);
    expect(llmOutputPriceCnyPerMillion, 8.0);
  });
}
