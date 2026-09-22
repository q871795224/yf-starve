# 动画独立验证

骑乘动画需要分三层检查：

1. **资源层**：`anim.bin` 是否真的包含目标 bank 和动作。
2. **预览层**：把 bank、build 和贴图导入 Spriter 或独立动画播放器，确认帧本身有变化。
3. **游戏层**：在 DST 中确认骑手实体的 bank、build、StateGraph、挂载关系和网络同步。

资源层不依赖 DST，可以在测试机断开时运行：

```bash
python3 tools/inspect_anim_bank.py \
  temp/reference-mods/RideableGrassGator/bank/wilsonbeefalo.zip

python3 tools/inspect_anim_bank.py \
  temp/reference-mods/RideableGrassGator/bank/wilsongrassbeef_15.zip \
  --contains bellow
```

参考模组把同一个 bank 拆成了很多 zip。要跨分片搜索，不必逐个文件执行检查：

```bash
# 先看每个 bank 有多少个不同动作
python3 tools/catalog_anim_banks.py --summary

# 再按关键词筛选候选动作
python3 tools/catalog_anim_banks.py --contains bellow
python3 tools/catalog_anim_banks.py --contains lancecharge
python3 tools/catalog_anim_banks.py --contains mount
```

`catalog_anim_banks.py` 会合并重复分片中的同名动作；方向版本仍会以 `_side`、`_upside` 等独立名称显示。输出包含 bank、动作名、帧数、帧率以及来源 zip。关键词可以重复传入；筛选条件之间按“任意一个命中”处理。

脚本只使用 Python 标准库，输入可以是 `anim.bin` 或包含它的 zip。它能报告 bank、动作名、帧数、帧率和每帧元素数量；它不能证明动作已经在游戏里显示。

## 预览工具链

- Klei 的[官方 Don’t Starve Mod Tools](https://github.com/kleientertainment/ds_mod_tools) 配合 Spriter 可以打开 SCML 项目，适合编辑和逐帧查看。
- 开源 [ktools](https://github.com/nsimplex/ktools) 的 `krane` 可以把 `anim.bin + build.bin` 转成 SCML。
- [DSTmodutils](https://github.com/ZzzzzzzSkyward/DSTmodutils) 附带 JSON 转换脚本和 `html/index.html` 动画播放器。播放器需要 `anim.json`、`build.json` 和 PNG 贴图；缺少完整 build 或贴图时只能检查动作元数据，不能还原完整角色。

这些工具都在 `temp/` 下临时使用，不进入模组发布包。当前参考模组里的 bank 是拆分追加的资源，`wilsonbeefalo.zip` 只含自定义 `lancecharge_*`；原版 `bellow` 所在的 bank 分片和完整 beefalo build 需要从测试机的 DST 安装目录补齐，不能用 gator 的 build 代替。

本次离线验证已经跑通：`BetterBeefalo/anim/player_mount_shoes.zip` 的 build、贴图和 `wilsonbeefalo` 动作可以在 HTML 播放器里逐帧显示；`wilsongrassbeef_15.zip` 配合 `grass_gator_build.zip` 也能显示 `bellow` 的 51 帧姿态变化。第二个结果只证明动作资源和播放器链路有效，最终 beefalo 外观仍要使用 DST 安装目录里的匹配 build。

## 当前工作区的逐帧预览

当前工作区已经准备了两个可直接打开的预览目录。启动一个只读 HTTP 服务，避免浏览器阻止本地 JSON 或贴图：

```bash
python3 -m http.server 8765 --bind 127.0.0.1 --directory temp/animation-lab
```

浏览器打开 <http://127.0.0.1:8765/index.html>，把对应目录里的 `anim.json` 和 `build.json` 拖到页面的“anim.json/build.json”区域，再把“贴图路径”设为下面的 URL，点击“贴图刷新”：

| 预览 | JSON 文件目录 | 贴图路径 | 重点动作 |
| --- | --- | --- | --- |
| 完整骑手装具参考 | `temp/animation-lab/player_mount_shoes/` | `http://127.0.0.1:8765/player_mount_shoes/images/` | `wilsonbeefalo / mount_shoes`、`dismount_shoes` |
| 战吼姿态参考 | `temp/animation-lab/bellow_preview/` | `http://127.0.0.1:8765/bellow_preview/images/` | `wilsongrassbeef / bellow` |

第二个目录使用的是参考模组的 gator build，只用于确认 `bellow` 的帧会改变骑乘组合体；它不代表最终牛的贴图。鼠标滚轮可以逐帧，播放按钮可以循环，bank 和 anim 下拉框用于切换动作。退出服务按 `Ctrl-C`。

## 游戏层验证

资源检查通过后，仍需在 DST 中验证：

- 骑乘后可见主体是骑手，动作应在 `wilson` / `wilson_client` 状态图中播放；
- 骑手的 `AnimState` 使用 `wilsonbeefalo` bank 和对应 beefalo build；
- 牛实体的 `beefalo` 状态可以负责声音、伤害和逻辑，但单独切换它不能证明骑乘画面会改变；
- `luajit tests/battle_cry_test.lua` 和 `luajit tests/animation_probe_test.lua` 只能验证 RPC、状态切换和动作名路由，不能替代画面验证。

## 从动作到功能的筛选顺序

先在播放器里确认姿态，再接入 StateGraph；不要一开始手工拼贴图。常见的可组合片段如下：

| 动作组 | 已发现的片段 | 可以承载的功能 |
| --- | --- | --- |
| 战斗 | `atk_pre_*` → `atk_*`，`player_atk_*`，`lancecharge_pre_*` → `lancecharge_loop_*` → `lancecharge_pst_*` | 牛命中时骑手同步攻击；蓄力冲撞 |
| 战吼/反馈 | `bellow`、`taunt`、`alert_pre/idle/pst`、`shake` | 战吼、警戒、技能反馈 |
| 移动 | `run_pre/loop/pst_*`、`idle_walk_pre/loop/pst_*` | 犁地、自动移动、冲撞过程 |
| 骑乘 | `mount`、`dismount`、`heavy_mount`、`buck` | 上下牛、被甩落、承受冲击 |
| 补给/采集 | `eat_pre/eat/eat_lag`、`quick_eat_*`、`graze2_pre/loop/pst` | 吃草、补给、自动收集的动作反馈 |

带有 `pre`、`loop`、`pst` 的组应按“准备 → 循环 → 收尾”播放：进入状态时 `PlayAnimation(pre)`，再 `PushAnimation(loop, true)`，结束时 `PushAnimation(pst, false)`。方向后缀如 `_side`、`_upside`、`_downside` 要和当前朝向对应；一次性动作如 `bellow`、`buck` 可以直接播放。
