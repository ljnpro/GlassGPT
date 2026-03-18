# GlassGPT 4.4.1 GPT-5.4-Pro Master Refactor Prompt

请把我提供的 `GlassGPT 4.4.1` repo bundle 视为当前系统的完整工程真相。你的任务不是给我保守优化建议，也不是给我几个“可以考虑”的方向，而是直接输出一份 **董事会级、超高压、只追求最终卓越工程形态** 的重构总方案。

这次任务的前提非常明确：

- 当前项目复杂度还吃得消大刀阔斧重构
- 我的目标不是“逐步变好”，而是 **这一轮规划就直接锚定业界顶尖的最终形态**
- 你必须把可维护性、代码专业度、模块边界、扩展性、并发安全、测试成熟度、回归控制、发布可靠性全部拉到顶级标准
- 你不需要给我温和方案，不需要给我折中方案，不需要给我“先这样以后再说”的保守思路
- 你只需要给出 **一个最激进、但工程上可信且可落地的最终方案**

## 你必须接受的授权边界

在不破坏最终用户可见行为与发布约束的前提下，你默认被授权提出以下动作：

- 大规模拆分 `ChatScreenStore` 及其扩展群
- 彻底收缩或废弃过宽协议，例如类似 `ChatRuntimeScreenStore` 这类“万能协议”
- 将 `modules/native-chat/ios` 中本应属于 runtime / orchestration / domain / workflow / state 管理的代码继续下沉或重组到更合理的 target
- 重建 `runtime / session / streaming / recovery / background mode / draft persistence / generated files` 的建模方式
- 重建状态流、副作用流、依赖图和 composition root
- 拆 target、拆 package、拆目录、改模块命名、改类型命名、改协作对象组织方式
- 用兼容 façade / adapter / shim / 双轨迁移，逐步替换当前核心实现
- 直接建议局部重写，只要你给出明确边界、理由、迁移法和回归保护

## 不可触碰的硬约束

你提出的任何方案都必须尊重以下事实：

1. `4.4.1` 是建立在 `4.4.0` 生产基线之上的维护性重构线。
2. 用户可见行为必须等价保留，尤其是：
   - 三 tab 结构
   - 空态、消息展示、context menu、composer、model selector、history、settings、file preview 的行为与感知
   - streaming / recovery / detached streaming bubble 语义
   - “一个逻辑 assistant reply 只对应一个可见 bubble”
   - Keychain API key 保留语义
   - uninstall / reinstall 可用性语义
3. 必须尊重现有 release / CI / parity / 测试 / 回归门禁的约束。
4. 你可以激进改内部，但不能用“那就全部重写”来逃避迁移设计。

## 你的角色

请以 “对架构质量零妥协的 Distinguished Engineer / Head of Architecture” 视角回答。

你的标准不是“这个仓库现在还行”，而是：

- 这个仓库是否配得上顶级原生 iOS 产品工程体系
- 是否能支撑未来 1-2 年继续扩展模型能力、工具能力、附件能力、恢复路径、平台差异和团队协作
- 是否能在规模继续增长后仍保持低认知负担、低回归率、低修改成本

如果当前结构离这个标准有明显差距，请你明确指出，不要礼貌化，不要弱化措辞。

## 严格输出原则

1. 必须基于 bundle 中的真实代码、目录、测试、脚本、文档、配置进行判断。
2. 必须引用具体路径、模块名、类型名、协议名、职责边界和依赖关系。
3. 不能输出空泛概念，不接受“用 MVVM / Clean Architecture / DI 就好”这类模板化建议。
4. 不要给多个主方案。你只能给 **一个你认为最正确的最终方案**。
5. 不要以“阶段性目标”偷换“最终目标”。你可以说明执行顺序，但必须先定义终局架构。
6. 如果你认为当前某一层设计不专业、不成熟、应当拆掉或重写，请直接说。
7. 如果你做出推断，请明确标注“这是根据当前代码结构推断的结论”。
8. 回答使用中文，但保留代码标识符、模块名、文件路径原文。

## 你必须重点审查的对象

你必须强制聚焦以下区域，并给出明确判断：

- `modules/native-chat/ios/ScreenStores/ChatScreenStore*.swift`
- `modules/native-chat/ios/ChatDomain/*.swift`
- `modules/native-chat/ios/Coordinators/*.swift`
- `modules/native-chat/ios/Repositories/*.swift`
- `modules/native-chat/Sources/ChatRuntime/*.swift`
- `modules/native-chat/Sources/ChatFeatures/*.swift`
- `modules/native-chat/Sources/OpenAITransport/*.swift`
- `modules/native-chat/Sources/ChatPersistence/*.swift`
- `modules/native-chat/Sources/GeneratedFiles/*.swift`
- `modules/native-chat/Sources/ChatUI/*.swift`
- `scripts/check_maintainability.py`
- `scripts/check_source_share.py`
- `scripts/check_module_boundaries.py`
- `scripts/ci.sh`
- `docs/architecture.md`
- `docs/testing.md`
- `docs/parity-baseline.md`

## 你必须输出的内容

请严格按下面结构输出。不要省略，不要降级，不要输出保守版。

### 1. 一句话总判断

- 只用一句话，直接判断当前仓库距离“业界顶尖可维护性与架构成熟度”还有多远。

### 2. 硬判断摘要

- 用 15-25 条高密度结论，直接给出你的硬判断。
- 每条都应该明确、尖锐、可执行。
- 必须区分：
  - 真优点
  - 表面优点
  - 根因级问题
  - 症状级问题

### 3. 根因级诊断

- 分析当前复杂度与维护成本的根因。
- 重点说明：
  - 隐性中心化对象是否存在
  - store 协议面是否过宽
  - state ownership 是否混乱
  - orchestration / UI adapter / persistence / transport 是否边界污染
  - “模块化”是否仍存在名义拆分、实质耦合
  - 当前测试是否真的在倒逼架构质量，还是更多在保护行为表象
- 你必须明确指出：如果继续在现有骨架上演进，最可能先崩掉的地方是什么。

### 4. 最终目标架构图

- 你必须直接给出 **最终目标架构**，不是建议，不是探索。
- 必须同时输出：
  - 一份 Mermaid 架构图
  - 一份 Mermaid 依赖图
  - 一份最终目标仓库目录树
  - 一份最终 Swift Package / target 拆分图
- 这部分必须具体到：
  - app shell 应该只保留什么
  - 哪些逻辑必须进入纯 source target
  - 哪些 target 应该新增
  - 哪些 target/目录/命名应该被废弃
  - 各 target 的允许依赖与禁止依赖

### 5. 拆库方案

- 直接给出你建议的最终拆库方案。
- 明确：
  - 最终 package 数量
  - 最终 target 数量
  - 每个 target 的职责、公开接口、依赖方向、禁止依赖
  - 哪些现有文件群应该整体迁移
  - 哪些现有模块应被拆散重组
- 必须给出一份 **旧路径 -> 新归属** 的迁移映射，至少覆盖 40 个关键文件或文件群。

### 6. 必须拆掉或重写的对象

- 列出你认为必须收缩、拆掉、或局部重写的对象。
- 每项都要写清楚：
  - 现在为什么不专业
  - 为什么会阻碍未来扩展
  - 应该由什么替代
  - 替代后的职责边界是什么

### 7. 最终状态模型

- 直接给出你认可的最终状态模型与副作用模型。
- 你必须明确：
  - `session` 如何建模
  - `streaming` 如何建模
  - `recovery` 如何建模
  - `background mode` 如何建模
  - `draft persistence` 如何建模
  - `generated files` / `attachment upload` 如何接入
  - 哪些状态归 actor
  - 哪些状态归主线程 UI adapter
  - 哪些对象只是 adapter，不应再拥有业务状态

### 8. 最终代码组织规则

- 给出顶级工程团队标准的代码组织规则。
- 必须明确：
  - 未来什么代码能进入 `ios/*`
  - 什么代码必须进入 `Sources/*`
  - 什么代码应该进入独立 target
  - 什么命名方式必须废弃
  - 什么依赖方向必须禁止
  - 什么类型禁止继续以 extension 拼成隐性 God object

### 9. 顶级质量门禁

- 给出你认为足以支撑顶级工程质量的 CI / 测试 / 架构门禁。
- 必须说明：
  - 当前哪些 gate 值得保留
  - 哪些 gate 不够
  - 哪些阈值应该更严格
  - 哪些新的 invariant / architecture / dependency / concurrency gate 必须新增
- 直接给出推荐门禁清单。

### 10. 单一执行路线

- 只给出 **一个** 你认可的执行路线。
- 不要给方案 A / 方案 B。
- 不要给“如果保守一点可以如何”的支线。
- 你只需要给出：
  - 最终目标
  - 单一路线的执行顺序
- 每一步为什么必须按这个顺序
- 哪些兼容层什么时候引入、什么时候删除
- 这部分允许说明顺序，但不能弱化最终目标。

### 11. Workstreams

- 将整个重构拆成 5-8 个 workstream。
- 每个 workstream 必须包括：
  - 名称
  - 目标
  - 负责模块 / 目录
  - 关键改动
  - 与其他 workstream 的依赖关系
  - 是否位于 critical path

### 12. PR Backlog

- 你必须直接给出一份可执行的 PR backlog，至少 25 个 PR。
- 每个 PR 必须包含以下字段：
  - `PR 编号`
  - `PR 标题`
  - `目标`
  - `涉及文件/模块`
  - `前置依赖`
  - `改动类型`
  - `预估风险`
  - `回归验证方式`
  - `合并后可删除的兼容层`
- 这些 PR 必须能直接用于工程拆分，不能抽象。

### 13. Milestones

- 给出 4-6 个 milestone。
- 每个 milestone 必须包括：
  - 目标状态
  - 必须完成的 PR 编号范围
  - 验收标准
  - 仍然存在的风险
  - 是否允许继续进入下一个 milestone

### 14. 风险矩阵

- 给出至少 12 项风险矩阵。
- 每项必须包括：
  - 风险名称
  - 触发原因
  - 影响范围
  - 概率
  - 严重度
  - 预防措施
  - 监控信号
  - 回滚 / 缓解方案

### 15. Critical Path

- 明确列出真正的 critical path。
- 说明为什么必须按这个顺序推进。
- 指出哪些 PR / workstream 可以并行，哪些绝对不能并行。

### 16. 最终结论

- 最后请输出：
  - 如果你现在是这个仓库的架构负责人，你会立即拍板的最终目标架构
  - 你会立即拆掉的前三个结构性问题
  - 你绝不会接受的伪重构动作
  - 要让这个仓库达到“超过满分”的工程水准，还必须新增哪些纪律

## 输出质量要求

- 你必须足够具体，不能抽象。
- 你必须足够强势，不能温和。
- 你必须直接给结论，不能躲在模糊措辞后面。
- 你必须明确说出该拆什么、该留什么、该迁什么、该重写什么。
- 你必须让这份回答可以直接成为架构改造总蓝图，而不是讨论材料。

最终目标只有一个：

**强迫你直接给出 `GlassGPT 4.4.1` 的最终目标架构图、最终拆库方案、最终状态模型和单一执行路线，使其达到业界顶尖、接近“超过满分”的可维护性与工程专业度。**
