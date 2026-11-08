## 更新内容

- AI 提供商：判定接口和整理接口改为选择提供商。判定可选 TypeSafe 官方、阿里百炼（填写业务空间 ID）和自定义接口；整理可选 DeepSeek、OpenAI、Anthropic 和自定义接口，自定义时可选 OpenAI 兼容或 Anthropic 格式。原有设置会自动对应到相应的提供商
- 整理接口支持 Anthropic API 格式；阿里百炼的判定请求按其上限每次最多 16 道题
- 校准向导：点「停止」立即中断整理并舍弃这一轮的结果，离开向导时也会停止；题库不够答题时按钮显示「开始整理」
- 校准向导：整理进度条一直缓慢前进，不再卡在某处；整理时的输出只显示已写完的行，并平滑向上滚动
- 后台整理：关闭开关后立即停止正在进行的后台整理；题库不会再因整理超过设定的上限
- 整理接口为 DeepSeek 时思考强度从最高降为高，整理更快；没有返回用量的请求也按估算计入每日上限

## Updates

- AI providers: both the judge and the organize endpoints now pick a provider. Judging offers TypeSafe, Alibaba Cloud Bailian (with your workspace ID) and a custom endpoint; organizing offers DeepSeek, OpenAI, Anthropic and a custom endpoint in OpenAI-compatible or Anthropic format. Existing settings map to the matching provider
- The organize endpoint supports the Anthropic API format; Bailian judge requests carry at most 16 questions, its documented limit
- Calibration wizard: "Stop" cuts the round off at once and discards its results, and leaving the wizard stops it too; the start button reads "Start organizing" while the question bank is too small to answer
- Calibration wizard: the organizing progress bar keeps moving slowly instead of stalling, and the streamed output only shows finished lines, scrolling them up smoothly
- Background organizing: turning the switch off stops a running background round right away, and a round no longer pushes the question bank past its cap
- DeepSeek reasoning effort drops from max to high for faster organizing; requests without a usage report are estimated toward the daily cap
