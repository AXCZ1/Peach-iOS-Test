# Peach iOS Test 当前交接

更新日期：2026-11-12。最新交付为独立 Peach App **构建 46**。普通 VLC 恢复构建 34 的配置和切速路径，已通过编译及 IPA 校验，待 iPhone 复测。用户实测构建 45 未解决问题，构建 34 仅有约 1 秒切速延迟，无卡死、掉帧或无声。

## 当前项目路径和运行方式

- 【PC PowerShell｜项目目录 `C:/Users/mo/Documents/Codex/Peach-iOS-Test`】独立 SwiftUI 项目，仓库 https://github.com/AXCZ1/Peach-iOS-Test，分支 `main`。
- 构建 46 源码 29d7740651ced31f3cdbd45f63221540d6d3ca30，Codemagic 6af4a99d6a24ea510088f900。VLC 对照构建 34 源码 f03f909b6cd2f35593c9c76834f63ebf7bf918db。构建 45 源码 0f45bc690e3691859e66a98a9f7a9c912afd2312。
- IPA C:/Users/mo/Downloads/NAS-unsigned .46.ipa，21,125,522 字节，SHA256 ba9aa91b318840e6af9db6f3e4eb5930c13a4741f87fa07c35bd3eac93366e63。构建 34、44、45 原 IPA 保留。
- Bundle ID `com.axcz1.peachios.test`，显示名 `Peach Test`，iOS 17.0+，iPhone ARM64，无签名；安装仍用用户现有签名方式。
- `codemagic.yaml` 的 `ios-unsigned-ipa` 调用 `scripts/build-unsigned-ipa.sh`；Pod 安装后使用 `PeachTest.xcworkspace` / `PeachTest` scheme。Codemagic 应用 ID `6aed85f0165a22c4d4b043a0`。API 凭据由进程环境提供，不写入仓库。
- 后端为用户自管 Peach 0.52.0；App 支持局域网地址和 HTTPS 域名，登录态及密码保存在设备。馆藏数量会变化，不沿用历史 54 部作为当前事实。本轮未重新探测后端。
- `C:/Users/mo/Documents/Codex/NAS-ios`、`C:/Users/mo/Documents/Codex/media-browser` 仅作参考，当前工作不修改它们。本项目没有需要同步软路由 HANDOVER 的既定双端安排。

## 当前功能状态

- 独立 App 已有馆藏、索引/分类、搜索与历史、筛选与排序记忆、详情、个人记录、随机连播、播放墙和系统小窗；管理入口以只读状态为主。功能清单参考 `FEATURE-MATRIX.md`，其中验收状态可能落后于最新代码。
- 原文件在 iPhone 上由 AVPlayer 或 VLCKit 4.0.0a25 解码，正式播放不回退 NAS HLS 转码。VLC 无首帧且已收到数据时可用软件解码重试一次；这不代表所有作品已能播放。
- 两套图片缓存必须区分：详情阅览图使用 `OfflinePreviews` 原尺寸 PNG，支持手动整库扫描、续做和补缺；进度条使用 `MediaBrowserSeekClient` / `SeekPreviewCache` 提前同步 NAS 已生成的 WebP 小图。NAS 不打缩略图包；进度条缓存改动不应改变详情原图。
- 构建 34 将进度条小图同步改为受限滚动并发、App 生命周期持有任务，离开设置页仍可继续；iOS 后台暂停后回到 App 续做。构建 36 合并快速拖动的缩略图请求并提前加载图库相邻原图。历史证据参考对应提交及 `artifacts/codemagic-*/`，不能仅凭实现认定真机问题已消失。
- 普通播放手势：左右各 25% 双击 ±10 秒，中央双击播放/暂停；同侧每次有效快进/退后重新开放 700ms 单击续窗。提示按实际累计位移显示 `+10 / +20 / +30` 或负数，已去掉快进/退图标；播放/暂停白色图标保留，暂停时常驻。
- 普通画面横滑跨度是全宽对应片长的 0.05；拖动时维持原播放/暂停状态，松手提交 seek。长按识别为 250ms，按下请求 2×、松手恢复 1×。播放墙的既有手势和内嵌播放器不套用普通播放器改动。
- 构建 40 的定向修改：撤回构建 38 的 `clock-master=monotonic`，恢复 VLC 默认音频主时钟；仅 `PlayerView(item:api:)` 创建的普通播放器通过工厂启用 `interactivePlayback: true`，设置 `network-caching=300`（默认原为 1000ms）。保留自适应 jitter，不在切速时强制 seek、暂停或重建。播放墙、随机连播、卡片预览仍用默认配置。用户随后报告长按 2× 仍有掉帧、延迟和卡死。
- 构建 41、43、44 分别尝试 VLC 媒体选项、逐级切速和立即切速。实测构建 41 好了一些，开始倍速时仍可能跳帧。构建 43 开始与结束都大约延迟一秒。构建 44 的普通播放器保留 `network-caching=220`、`clock-jitter=0`、`no-audio-time-stretch`。这些参数的实际效果未在真机测量。
- 构建 46 的普通 VLC 走构建 34 的默认缓存、时钟和音频配置，通过原播放入口切换 2×/1×。VLC 后端源码与 34 一致。普通 AVPlayer 仍用构建 45 的直接切速。手势、续播、跳转、小窗和播放墙沿用原路径。
- 实现见 `PlaybackController.swift`、`LocalOriginalPlayer.swift`、`VLCOriginalPlayer.swift` 和 `PlayerView.swift`。回归见 `OriginalPlaybackTests.swift` 与 `PlaybackLifecycleTests.swift`。
- 本地 14 项交互回归、云端 Debug/Release 核心测试、iPhone ARM64 Release 编译及 IPA 校验通过。内嵌 VLCKit 与构建 34 二进制逐字节相同。证据见 artifacts/codemagic-46/。

## 当前稳定备份

- **没有已确认消除倍速问题的稳定版本。** 构建 37 的 IPA 仍在 Downloads，源码 `d544e7a1b160a8523a2e63bfa4ef393ff1b7fb29`；用户已报告 VLC 实际切速和松手恢复各延迟约 1–2 秒，只能作为回归前比较点，不能称为无缺陷稳定版。
- 构建 38（`207c3385dcc8d44da0dace2a02037a14d0960693`）强改时钟后，用户报告卡死、无声、声音卡住和掉帧；**不要恢复该时钟方案，也不要推荐构建 38 回退**。
- 构建 39（`37eff0c87bbeee3bd3421dc0c9bc4f1b4fe3d12b`，Codemagic `6af409e2785c68ee929f4ccb`）只撤回时钟并删快进图标，云端成功但未作为最终修复交付；用户明确不接受仅回退旧状态作为解决方案。当前继续点是构建 46。构建 43 被用户评为开始和结束都大约延迟一秒。构建 41 只被用户评为好了一些，约一半次数仍会触发，开始 2× 仍跳帧。构建 40 的真机问题尚未被新包证实消除。
- 既有源码备份保留：`backups/preview-player-20261109-030505/source.zip`（`0c972b1`）、`backups/local-preview-decode-20261108-041442/source.bundle`（`02bd7ee`）、`backups/vlc-pip-20261108-001740/source.bundle`（`d163e33`）及其他历史备份。它们只覆盖源码，不代表后端或媒体备份；本轮不新增或清理备份。
- NAS 构建 82 和原工程未在本轮修改或重新打包；历史校验见 Git 中的旧交付记录。本轮未重复验证其文件哈希。

## 必须遵守的规则

- 权威规则：本项目 `AGENTS.md`、`C:/Users/mo/.codex/instructions/git-safety.md`、`C:/Users/mo/.codex/instructions/recovery-handover.md`。工作区 `AGENTS.md` 是用户提供的未跟踪文件，保留，不混入交接或代码提交。
- 只改独立 Peach App；用户已决定不接入 NAS iOS。域名用户自行配置，不修改服务端、源媒体、NAS 项目、自动采集或播放墙内嵌播放器。
- 仅手动触发 Codemagic `ios-unsigned-ipa`；同一提交/工作流已有构建不重复启动，不为文档构建。GitHub Actions 保持禁用；未经明确授权不启动 Simulator。
- iPhone 真机反馈才是播放和手势验收结论。编译、API 成功、纯逻辑测试都不能证明 VLC 音画已恢复正常。限定修改范围，检查共享组件调用方，不借机改缓存、布局或其他播放器。
- 当前代码提交已在远程；仅为实际交接整理并提交 HANDOVER。不得覆盖已有 Downloads 同名文件，必须先核对哈希。

## 未解决问题

- **真实切速延迟仍待定位。** 用户已确认构建 34 只剩约 1 秒延迟，45 未解决问题。构建 46 先恢复 34 的 VLC 路径以排除后续配置回归，尚无真机结果。用户此前确认 2× 提示及时，延迟在实际音画切速。
- 版本更正：直接读取 iPhone IPA，构建 20 的 MobileVLCKit 3.7.3 包含 libVLC 3.0.23，构建 44 的 VLCKit 4.0.0a25 包含 `4.0.0-dev-39228-g48b12f61c8` 及 VLC 小窗渲染层。旧交接以 3.0.23 推导构建 41–44 的时钟偏移和冲刷阈值，不能据此解释当前 4.x 的行为。用户选择保留 VLC 小窗，仅采用 NAS 播放控制方式。
- 历史 SONE-081 在构建 27 仍黑屏，用户没有给出后续解决回执；构建 40 未修这个单片问题。
- 快拖进度条黑图、详情原图预缓存后偶发转圈、拖进度画面静止均已有定向改动，但本会话没有收到完整真机通过回执；不要将旧未确认问题一并宣称解决。
- 播放列表改名/删除/排序、部分管理写操作和照片墙等未完成范围参考 `FEATURE-MATRIX.md`，不属于当前倍速修复任务。

## 下一步任务

1. 在构建 46 上用同一部 VLC 影片复测。按住和松手都观察实际音画，先确认卡死、掉帧、无声是否回到 34 的表现，再单独记录剩余切速延迟。
2. 检查 VLC 小窗进入和恢复，结合实际出帧和播放进度判断倍速效果。
3. 一并看快进累计秒数和 700ms 续点，以及普通拖动、暂停、退出和 PiP。播放墙内嵌播放器不应改变。
4. 只在有新的真机证据后再改代码和构建。
