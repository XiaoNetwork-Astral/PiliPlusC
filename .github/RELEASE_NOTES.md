## 更新内容

- AI 屏蔽：去掉总敏感度，每个内置类别各有自己的屏蔽阈值，可在类别编辑页单独调整
- 校准向导：答完题后只调整被回答的那个类别，单次最多调 0.03，不再一次把所有类别推到上限
- 校准向导：收集池限制同一来源的占比，抽样按来源分散，整理提示词要求覆盖不同话题
- 校准向导：题库里题目够多时直接开始答题，不再先进整理页；整理页进度条改为平滑前进，思考文字统一从下往上滚动
- 类别规则页新增「重置类别规则」，规则列表右上角新增「一键重置」，设置里新增「恢复默认」（保留账号登录、密钥和规则列表）

## Updates

- AI blocking: the overall sensitivity is gone. Every built-in category now has its own threshold, adjustable on the category page
- Calibration wizard: answers only adjust the category they belong to, by at most 0.03 per round, instead of pushing every category to the cap
- Calibration wizard: the pool caps how much one source can take, sampling spreads across sources, and the prompt asks for varied topics
- Calibration wizard: a ready question bank starts the quiz directly, the organizing page has a smooth progress bar, and the thinking text scrolls evenly
- Added "Reset category rules" on the category page, "Reset" in the rule list menu, and "Restore defaults" in settings (login, keys and rule lists are kept)
