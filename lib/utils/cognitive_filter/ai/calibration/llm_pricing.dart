/// 整理接口的费用折算
///
/// 只依赖 Dart 核心库，方便单独写单元测试。价格按 DeepSeek 官方人民币价目
/// 取高峰时段，宁可高估也不漏记；缓存命中价更低，这里不区分。非 DeepSeek
/// 模型也用同一份价格估算。

/// 输入价格，人民币元/百万 token
const double llmInputPriceCnyPerMillion = 2.0;

/// 输出价格，人民币元/百万 token
///
/// 接口的 `usage.completion_tokens` 已含思考 token，直接用即可。
const double llmOutputPriceCnyPerMillion = 8.0;

/// 把输入/输出 token 数折算成人民币元
///
/// 负数按 0 计，避免存储异常时算出负费用。
double llmCostCny(int inputTokens, int outputTokens) {
  final input = inputTokens < 0 ? 0 : inputTokens;
  final output = outputTokens < 0 ? 0 : outputTokens;
  return input * llmInputPriceCnyPerMillion / 1e6 +
      output * llmOutputPriceCnyPerMillion / 1e6;
}
