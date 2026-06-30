# 06 — 像素宠物系统

> 目标：用 Codex 会话状态驱动像素宠物动画，并用用户历史累计 token 消耗提供 0-100 级长期成长。

---

## 实现范围

- 宠物随 Codex 状态切换：idle / thinking / streaming / awaiting / error
- 首次启动读取历史全局 token 累计，并据此计算等级、进度和同宠物变形阶段
- 后续按全局 token 正向增量继续成长
- 每累计 25M 成长 tokens 触发一次进食动画
- 跨等级时触发一次升级动画，即使单次 snapshot 跨多级也只播放一次
- PNG 帧素材优先，缺失时自动使用 SwiftUI Canvas 占位绘制
- Pill 内宠物按安全锚点巡游，避开 token 数字区域

---

## 文件结构

```
CodexIsland/
├── Core/
│   ├── GlobalTokenUsageSnapshot.swift
│   └── PetEvolutionStore.swift
├── UI/
│   ├── Components/
│   │   ├── PetAnimation.swift
│   │   ├── PixelPetView.swift
│   │   ├── PlaceholderPetView.swift
│   │   ├── RoamingPetView.swift
│   │   └── PulseRingView.swift
│   └── NotchWindow/
│       └── NotchIslandView.swift
└── Assets.xcassets/
    └── PixelPet/
```

---

## 等级曲线

`PetLevelCurve` 使用平方曲线：

```swift
tokensRequired(level) = 10_950_000 * level * level
```

| 等级 | 累计 tokens | 3亿/天约需 |
|---:|---:|---:|
| Lv.5 | 273.75M | 约 1 天 |
| Lv.10 | 1.095B | 约 4 天 |
| Lv.50 | 27.375B | 约 91 天 |
| Lv.100 | 109.5B | 约 365 天 |

成长 token 计算规则：

1. 首次收到 `global_token_usage.total_tokens` 时，将历史累计写入 `earnedTokens`
2. 首次导入历史累计只更新等级和形态，不回放历史进食/升级动画
3. 后续 snapshot 只累加正向 delta：`max(0, totalTokens - lastObservedTotalTokens)`
4. 如果全局总数回退，不扣等级，也不重复计入
5. 旧版 `unlockedStageRank` / `prestige` 不迁移到新等级

---

## 变形阶段

宠物始终是同一只 Codex Core，只随等级累加新的身体特征和能量效果；不是切换成不同宠物。第一版自动展示当前等级可用的最高变形阶段，不做手动选择器。

| 等级段 | `PetForm.assetName` | 变形阶段 | 解锁动作 |
|---:|---|---|---|
| 0-9 | `codex_core` | Core 初始体 | 基础呼吸、思考、输出、等待、吃 token |
| 10-19 | `codex_core_antenna` | Core 双叶天线 | `happy_bounce` |
| 20-29 | `codex_core_ripple` | Core 流光纹路 | `nap` |
| 30-39 | `codex_core_shell` | Core 软壳护甲 | `bubble_think` |
| 40-49 | `codex_core_spark` | Core 火花节点 | `output_burst` |
| 50-59 | `codex_core_glider` | Core 滑翔翼片 | `hover_idle` |
| 60-69 | `codex_core_shield` | Core 护盾壳层 | `shield_wait` |
| 70-79 | `codex_core_crystal` | Core 晶体环轨 | `token_orbit` |
| 80-89 | `codex_core_star` | Core 星环冠冕 | `celebrate_dance` |
| 90-100 | `codex_core_spirit` | Core 灵体光核 | `spirit_idle`；Lv.100 解锁 `max_victory` |

---

## 动画清单

| 触发 | 动画名 | 帧数 | 帧率 | 循环 |
|------|------|------:|------:|------|
| Idle | `idle_breathe` | 8 | 8fps | 无限 |
| Idle 随机插播 | `idle_stretch` | 12 | 8fps | 1 次 |
| Lv.10 Idle 插播 | `happy_bounce` | 10 | 10fps | 1 次 |
| Lv.20 Idle 插播 | `nap` | 12 | 6fps | 1 次 |
| Thinking | `think_sweat` | 8 | 8fps | 无限 |
| Lv.30 Thinking | `bubble_think` | 8 | 8fps | 无限 |
| Streaming | `talk_walk` | 8 | 12fps | 无限 |
| Lv.40 Streaming | `output_burst` | 8 | 12fps | 无限 |
| Lv.50 Idle | `hover_idle` | 8 | 8fps | 无限 |
| AwaitingInput | `await_jump` | 10 | 10fps | 无限 |
| Lv.60 AwaitingInput | `shield_wait` | 10 | 10fps | 无限 |
| Error | `error_fall` | 10 | 8fps | 1 次 |
| 进食 | `eat_token` | 8 | 8fps | 1 次 |
| Lv.70 进食 | `token_orbit` | 12 | 10fps | 1 次 |
| 升级 | `evolve_glow` | 8 | 8fps | 1 次 |
| Lv.80 升级 | `celebrate_dance` | 12 | 10fps | 1 次 |
| Lv.90 Idle | `spirit_idle` | 8 | 8fps | 无限 |
| Lv.100 升级 | `max_victory` | 16 | 12fps | 1 次 |

状态映射位于：

[PetAnimation.swift](/Applications/APP/Codex-Island/CodexIsland/UI/Components/PetAnimation.swift)

---

## 素材规范

运行时优先查找变形阶段专属 PNG 帧：

```
优先命名：pet_{form_asset_name}_{animation_name}_{frame_index:02d}.png
兼容命名：pet_{animation_name}_{frame_index:02d}.png
示例：pet_codex_core_idle_breathe_00.png
示例：pet_codex_core_spirit_max_victory_15.png
位置：CodexIsland/Assets.xcassets/PixelPet/
```

素材要求：

| 属性 | 规格 |
|------|------|
| 单帧尺寸 | 24x24 px @1x，48x48 px @2x |
| 背景 | 透明 |
| 风格 | 圆润现代像素风，深色粗轮廓，高光块面 |
| 插值 | `.interpolation(.none)`，禁止模糊缩放 |

当前仓库未放入正式 PNG 帧素材；`PixelPetView` 找不到图片时会自动使用 `PlaceholderPetView` 的 SwiftUI Canvas 占位绘制。

---

## Notch UI 接入

- Pill：`RoamingPetView` 使用当前变形阶段和等级，并跟随 Codex 状态巡游
- Expanded：显示当前宠物、`Lv.N`、等级经验条、成长累计和下一等级差额
- AwaitingInput：宠物动画切换为等待态，并继续叠加 `PulseRingView`

---

## 验证项

建议每次改动后执行：

```bash
xcodegen generate
xcodebuild test -project CodexIsland.xcodeproj -scheme CodexIsland -destination 'platform=macOS'
make build-macos
```

重点检查：

- 首次历史 token 会参与等级，但不回放历史动画
- 3 亿累计 tokens 对应 Lv.5
- Lv.100 对应 109.5B 累计 tokens
- Lv.0 / Lv.5 / Lv.50 / Lv.99 / Lv.100 展开面板文案不溢出
- 无正式 PNG 时 Canvas 占位宠物仍可完整显示
