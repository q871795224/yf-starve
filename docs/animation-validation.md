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

项目内置了一个整理过布局的浏览器，不需要拖文件或手动填写贴图路径。启动服务：

```bash
python3 tools/serve_animation_lab.py
```

浏览器打开 <http://127.0.0.1:8765/tools/animation-lab/index.html>。页面会自动载入“骑手装具”预览。页面按三层关系组织资源：**外观 / Build → 动作资源集 → 具体动作 Clip**。当前有两个已经具备完整可视 build 的外观组和五个动作资源集：

| 外观 / 动作资源集 | 内容 | 重点动作 |
| --- | --- | --- |
| 普通牛 / Beefalo → 骑手装具 | 完整 rider + beefalo build，2 个 Clip | `mount_shoes`、`dismount_shoes` |
| 普通牛 / Beefalo → 蓄力冲撞 | `wilsonbeefalo`，24 个 Clip | `lancecharge_pre/loop/pst_*` |
| 水草牛 / Grass Gator → 基础与战斗 | gator build，23 个 Clip | `bellow`、`atk_*`、`graze*`、`alert_*`、`taunt`、`shake` |
| 水草牛 / Grass Gator → 骑乘与补给 | gator build，15 个 Clip | `mount`、`dismount`、`buck`、`eat_*` |
| 水草牛 / Grass Gator → 移动 | gator build，18 个 Clip | `run_pre/loop/pst_*` |

左侧第一层是外观组，下面的按钮是动作资源集；中间的 Bank 是该资源集固定使用的动画身份，具体动作在 Clip 下拉框中选择，选项会显示帧数和总时长。默认播放模式是单次、0.5 倍速；也可以切换循环或每次循环间隔 0.5 秒。页面按外观固定镜头缩放，切换同一头牛的动作不会重新放大。快捷键是空格播放/暂停、左右方向键逐帧。退出服务按 `Ctrl-C`。

水草牛的动作预览使用参考模组的 gator build，所以它与普通 Beefalo 是两种外观/坐骑资源。它用于确认动作帧和 StateGraph 组合方式；最终牛外观仍要按目标坐骑选择匹配 build。`wilsongrassbeef_water` 还有水中动作分片，但当前没有单独的完整水中 build 预览，因此仍由目录命令查看元数据。

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
