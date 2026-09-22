# 项目开发约定

## DST 骑乘动画的显示主体

- 未骑乘时，牛的可见动作由牛实体的 `AnimState` 和 `beefalo` 动画银行负责。
- 骑乘后，原版会把骑手切换到 `wilsonbeefalo` 动画银行，并把牛的外观 build 应用到骑手的 `AnimState`；画面上的骑手与牛组合体主要由骑手实体渲染。
- 因此骑乘状态下的可见动作必须优先在骑手的 `wilson` / `wilson_client` 状态图中播放，并使用 `wilsonbeefalo` 银行中存在的动画名，例如 `bellow`。
- 只调用 `beefalo.sg:GoToState(...)` 可以改变牛的逻辑状态、声音或伤害流程，但不能当作骑乘画面已经会改变；要单独确认骑乘组合体的可见动画。

## 相关概念

- **动画银行（bank）**：同一套视觉骨架可使用的动作集合，例如 `wilsonbeefalo`。
- **动画片段（animation）**：银行中的具体动作，例如 `bellow`、`run_loop`。
- **Build**：动作显示所需的图片、符号和材质组合。
- **StateGraph**：决定何时进入状态、播放哪个片段以及何时结算逻辑。

实现或排查骑乘动作时，先确认目标动作属于哪个 bank，再分别检查服务器逻辑状态、客户端状态图和可见 `AnimState`；不要把牛实体的 `beefalo` 动画状态等同于骑乘组合体已经显示。

## 独立验证边界

- `anim.bin` 可以脱离 DST 解析和预览；资源层检查应先确认 bank、动作名、帧数和帧率。
- 一个 zip 往往只是同名 bank 的追加分片。看到 `wilsonbeefalo.zip` 中没有 `bellow`，不能推断原版 bank 没有 `bellow`。
- 预览工具需要匹配的 `build.bin` 和贴图。不要拿其他生物的 build 代替 beefalo build 来判断骑乘组合体是否正确。
- 独立预览只能证明资源帧存在；RPC、StateGraph、挂载主体和联机同步仍要在 DST 中验证。
