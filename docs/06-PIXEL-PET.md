# 06 — 像素宠物系统

> 目标：实现由 Codex 会话状态驱动的像素宠物动画，并接入 05 的 Notch Island UI。

---

## 实现状态

✅ 已实现并通过本地验证。

当前范围只包含像素宠物自身能力：

- 状态到动画的映射
- PNG 帧素材加载约定
- 无素材时的 SwiftUI 像素占位绘制
- Idle 随机伸懒腰插播
- AwaitingInput 红色脉冲光圈叠加
- Error 单次倒地动画
- 全局 token 每累计 10M 触发一次进食动画
- 根据所有 Codex sessions 的累计 token 进化，不按单会话计算
- Pill 内宠物按安全锚点巡游，避开 token 数字区域
- 接入常驻 Pill 与 Hover Expanded 两种主要显示形态

---

## 文件结构

```
CodexIsland/
├── Core/
│   ├── EventBus.swift
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
        └── Contents.json
```

---

## 动画清单

| Codex 状态 / 触发 | 动画名 | 帧数 | 帧率 | 循环 | 当前实现 |
|------|------|------:|------:|------|------|
| Idle | `idle_breathe` | 8 | 8fps | 无限 | ✅ |
| Idle 随机插播 | `idle_stretch` | 12 | 8fps | 1次 | ✅ |
| Thinking | `think_sweat` | 8 | 8fps | 无限 | ✅ |
| Streaming | `talk_walk` | 8 | 12fps | 无限 | ✅ |
| AwaitingInput | `await_jump` | 10 | 10fps | 无限 | ✅ |
| AwaitingInput 叠加 | `await_ring` | - | - | 无限 | ✅ `PulseRingView` |
| Error | `error_fall` | 10 | 8fps | 1次 | ✅ |
| 全局 token 进食 | `eat_token` | 8 | 8fps | 1次 | ✅ |
| 进化光效 | `evolve_glow` | 8 | 10fps | 1次 | ✅ |

状态映射位于：

[PetAnimation.swift](/Applications/APP/Codex-Island/CodexIsland/UI/Components/PetAnimation.swift)

---

## 素材规范

运行时会优先查找 Asset Catalog 中的 PNG 帧：

```
优先命名：pet_{stage}_{animation_name}_{frame_index:02d}.png
兼容命名：pet_{animation_name}_{frame_index:02d}.png
示例：pet_sprout_drake_idle_breathe_00.png
示例：pet_idle_breathe_00.png ~ pet_idle_breathe_07.png
位置：CodexIsland/Assets.xcassets/PixelPet/
```

素材要求：

| 属性 | 规格 |
|------|------|
| 单帧尺寸 | 24x24 px @1x，48x48 px @2x |
| 背景 | 透明 |
| 风格 | 像素风，建议不超过 16 色 |
| 插值 | `.interpolation(.none)`，禁止模糊缩放 |

当前仓库未放入正式 PNG 帧素材；`PixelPetView` 找不到图片时会自动使用 `PlaceholderPetView` 的 SwiftUI Canvas 占位绘制。

---

## 进化阶段

[PetEvolutionStore.swift](/Applications/APP/Codex-Island/CodexIsland/Core/PetEvolutionStore.swift) 使用 `global_token_usage.total_tokens` 驱动阶段：

| 阈值 | 阶段 | 说明 |
|------:|------|------|
| `0` | `egg` | 初始蛋/幼体 |
| `50M` | `hatchling` | 幼龙，基础呼吸和短跳 |
| `250M` | `sprout_drake` | 明显角/翼，本机历史量级通常在这一档 |
| `1B` | `glider` | 翼更大，巡游更轻快 |
| `5B` | `guardian` | 加入更强尾焰/光效 |
| `20B` | `ancient` | 高阶形态 |

`20B` 之后每增加 `20B` 增加 prestige 等级，不再改变基础体型。

首次启动收到历史全局 token 时只设置当前阶段，不播放历史进化动画；运行期间跨过阈值才触发一次 `evolve_glow`。

---

## Notch UI 接入

[NotchIslandView.swift](/Applications/APP/Codex-Island/CodexIsland/UI/NotchWindow/NotchIslandView.swift) 已接入 `PixelPetView`：

- Pill：`RoamingPetView` 在 440pt 胶囊内按锚点巡游
- Expanded：显示 48pt 宠物、当前状态、四格 token 卡片和历史趋势
- 宠物动画跟随 Codex 状态：idle / thinking / streaming / awaiting / error

---

## 进食触发

[PetEvolutionStore.swift](/Applications/APP/Codex-Island/CodexIsland/Core/PetEvolutionStore.swift) 监听 Swift IPC 收到的全局 token 快照：

1. `TokenStore` 继续显示当前 active session 的 token 数字
2. `PetEvolutionStore` 使用所有 sessions 的 `total_tokens`
3. 全局 token 每增加 `10M` 发布一次 `feedTrigger`
4. `PixelPetView` 收到触发后插播一次 `eat_token`
5. 触发 milestone 保存到 `UserDefaults`，重启后不重复播放

---

## 验证结果

已执行：

```bash
xcodegen generate
(cd codex-watcher && cargo test)
python3 scripts/ipc_smoke_test.py codex-watcher/target/debug/codex-watcher
make build-macos
```

结果：

- Rust `cargo test`：39 passed
- IPC smoke test：通过，包含全局 token replay 与多 session 累计
- macOS Debug build：`BUILD SUCCEEDED`
- Asset Catalog 可编译
- 新增 SwiftUI 组件可编译进 App

---

## 剩余依赖

- 需要正式 PNG 帧素材替换当前 Canvas 占位绘制
- 需要继续做真实 Codex 长时间运行下的视觉巡游截图复验
