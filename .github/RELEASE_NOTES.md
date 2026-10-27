## 更新内容

- AI 屏蔽：去掉总敏感度，每个内置类别各有自己的屏蔽阈值，可在类别编辑页单独调整，类别规则页新增「重置类别规则」
- 校准向导：答题后只调整被回答的类别，单次最多调 0.03；收集样本按来源分散，整理时覆盖不同话题；老题库里没有类别记录的题也能参与调整
- 校准向导：题库里题目够多时直接开始答题，整理页进度条平滑前进，答题页改为居中排版
- 后台整理：打开认知滤网设置页期间暂停，离开后再继续，避免开始校准时接上跑到一半的整理
- 规则列表右上角新增「一键重置」，设置里新增「恢复默认」（保留账号登录、密钥和规则列表）

## Updates

- AI blocking: the overall sensitivity is gone. Every built-in category now has its own threshold on the category page, and the category page gains "Reset category rules"
- Calibration wizard: answers only adjust the category they belong to, by at most 0.03 per round; samples are spread across sources and topics, and old questions without a category record still count
- Calibration wizard: a ready question bank starts the quiz directly, the organizing page has a smooth progress bar, and the quiz page is centered
- Background organizing: paused while the cognitive filter settings are open and resumed after, so starting a calibration no longer joins a round that is already halfway through
- The rule list menu gains "Reset", and settings gain "Restore defaults" (login, keys and rule lists are kept)
