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

脚本只使用 Python 标准库，输入可以是 `anim.bin` 或包含它的 zip。它能报告 bank、动作名、帧数、帧率和每帧元素数量；它不能证明动作已经在游戏里显示。

## 预览工具链

- Klei 的[官方 Don’t Starve Mod Tools](https://github.com/kleientertainment/ds_mod_tools) 配合 Spriter 可以打开 SCML 项目，适合编辑和逐帧查看。
- 开源 [ktools](https://github.com/nsimplex/ktools) 的 `krane` 可以把 `anim.bin + build.bin` 转成 SCML。
- [DSTmodutils](https://github.com/ZzzzzzzSkyward/DSTmodutils) 附带 JSON 转换脚本和 `html/index.html` 动画播放器。播放器需要 `anim.json`、`build.json` 和 PNG 贴图；缺少完整 build 或贴图时只能检查动作元数据，不能还原完整角色。

这些工具都在 `temp/` 下临时使用，不进入模组发布包。当前参考模组里的 bank 是拆分追加的资源，`wilsonbeefalo.zip` 只含自定义 `lancecharge_*`；原版 `bellow` 所在的 bank 分片和完整 beefalo build 需要从测试机的 DST 安装目录补齐，不能用 gator 的 build 代替。

## 游戏层验证

资源检查通过后，仍需在 DST 中验证：

- 骑乘后可见主体是骑手，动作应在 `wilson` / `wilson_client` 状态图中播放；
- 骑手的 `AnimState` 使用 `wilsonbeefalo` bank 和对应 beefalo build；
- 牛实体的 `beefalo` 状态可以负责声音、伤害和逻辑，但单独切换它不能证明骑乘画面会改变；
- `luajit tests/battle_cry_test.lua` 和 `luajit tests/animation_probe_test.lua` 只能验证 RPC、状态切换和动作名路由，不能替代画面验证。
