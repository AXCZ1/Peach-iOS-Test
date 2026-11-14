# Peach iOS Test 当前交接

更新日期：2026-11-14。最新且用户确认的**当前稳定构建**为独立 Peach App **构建 56**（提交 `24cddcc`，Codemagic `6af86196cd5a07c6844f96b0`），已完成 4K MKV/退出回收修复（构建 50–51）、全模块运行日志采集与软路由接收清理链路（构建 52）、大图模式 1 秒静音且 ≥65% 封面续播预览，以及普通 VLC 播放器 `:clock-master=input` 即时切速与 `VLCAVSampleAudioSyncBridge` 2×/1× 音频时钟补偿修复（构建 53–56）。云端 ARM64 Release 编译与 IPA 校验通过，用户已确认将构建 56 作为当前稳定构建。

## 当前项目路径和运行方式

- 【PC PowerShell｜项目目录 `C:/Users/mo/Documents/Codex/Peach-iOS-Test`】独立 SwiftUI 项目，仓库 https://github.com/AXCZ1/Peach-iOS-Test，分支 `main`。
- **构建 56（当前稳定构建）**：源码 `24cddcc351a55acba5128a5d7c8bc5b6d1f4031c`（含功能提交 `0e2639bdf321df5978e54a98fa77868ded8a3f1d` 与语法修正 `24cddcc`），Codemagic `6af86196cd5a07c6844f96b0`（恢复共享 `VLCMediaPlayer()` + `:clock-master=input`，并新增 `VLCAVSampleAudioSyncBridge` 修复 `2×`/`1×` 音频缓冲估算漂移与冲刷）。历史对照构建：构建 55 `0e2639bdf321df5978e54a98fa77868ded8a3f1d`（Codemagic `6af85fb731cbfae02df82f78`，编译语法报错无 IPA）、构建 54 `0ed00fda029d58d22039fa7f8404339ca855353f`（Codemagic `6af852b6367f76daa2828825`，`--no-audio-time-stretch` 实验已撤回）、构建 53 `7de427ca571c27a546a191d14f5e91c2e5dbdbe6`（Codemagic `6af8492e3b2dc91b3891b175`，首次验证 `:clock-master=input` 消除画面切速延迟，但 `2×` 有静音重采样日志警告）、构建 52 `a30021737e0ffc6b0c45f2266fe6296112b7b188`（Codemagic `6af78987638832d0f45cf595`）、构建 51 `e4c16342be9b03be52b37e629fb6fc196ffb2d2f`（Codemagic `6af7800ee1236d9c61f441e2`）、构建 50 `438edb1c25af153e056c7b02937cb9a1d4ec4a36`（Codemagic `6af757c4f73ae9651430f55b`）、构建 49 `2a08092c837a5588cee8d424358a0bdd6867101c`（Codemagic `6af4cb0a3e65a1d3c042a5cb`）、构建 47 `695566398022edf9b83750295c70f783c7daea10`（Codemagic `6af4b41920423984be1c929b`）、旧基线构建 46 `29d7740651ced31f3cdbd45f63221540d6d3ca30`、VLC 对照构建 34 `f03f909b6cd2f35593c9c76834f63ebf7bf918db`。
- **最新与稳定 IPA**：`C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.56.ipa`（`21,300,618` 字节，SHA256 `37f360f0507f8bbbb21e22224b4d497dc3be23de651865999e1c9ee7926be63b`；Downloads 中原有 `NAS-unsigned .56.ipa` 来自旧工程，`2,834,870` 字节，SHA256 `4b9446d9be6c1a1dfbae5c4b9d86a6506e7cf07e45c918b7b748f7cdf9280bc0`，未覆盖）。历史 IPA 保留：`Peach-iOS-Test-unsigned.54.ipa`（`21,288,290` 字节，SHA256 `a20e14095f2104ccab75a558914393dbc1ea4dfd1dee68b60a6d9dae607e6068`）、`Peach-iOS-Test-unsigned.53.ipa`（`21,287,900` 字节，SHA256 `396e0d94db52cd0132031dff731b9c683976af707250171b58c7ad4f1de4a618`）、`Peach-iOS-Test-unsigned.52.ipa`（`21,288,115` 字节，SHA256 `facc632509a67ab1a5adee97111cd5377eebb0a4a3e325a1d34c584bebe490f2`）、`NAS-unsigned .51.ipa`（`21,137,763` 字节，SHA256 `74c56b4757217c15d786ba1e3680357073f3096eb87b4e5be819af69b6b36bb`）及构建 50/49/47/46 IPA。
- Bundle ID `com.axcz1.peachios.test`，显示名 `Peach Test`，iOS 17.0+，iPhone ARM64，无签名；安装仍用用户现有签名方式。
- `codemagic.yaml` 的 `ios-unsigned-ipa` 调用 `scripts/build-unsigned-ipa.sh`；Pod 安装后使用 `PeachTest.xcworkspace` / `PeachTest` scheme。Codemagic 应用 ID `6aed85f0165a22c4d4b043a0`。API 凭据由进程环境提供，不写入仓库。
- 后端为用户自管 Peach `0.52.0`；App 支持局域网地址和 HTTPS 域名，登录态及密码保存在设备。软路由侧（`root@192.168.5.5`，目录 `/mnt/ssd/apps/peach`）通过 `compose.yaml` 在原有 `192.168.5.5:8900` 端口前新增轻量网关与日志接收容器：`peach-edge`（Nginx `/mnt/ssd/apps/peach/ios-logging/nginx.conf`）将 `POST /api/ios-logs` 反代到 `peach-log-receiver:8901`（`/mnt/ssd/apps/peach/ios-logging/receiver.py`），其余请求透传 `peach:8900`（不新增公网端口，Peach 主服务未修改）；日志按 JSON Lines 追加到 `/mnt/ssd/apps/peach/ios-playback.jsonl`，由容器内 30 秒后台线程及宿主机 `*/5 * * * *` cron（`# peach-ios-log-prune`）按日志时间戳清理超过 1 小时记录。
- `C:/Users/mo/Documents/Codex/NAS-ios`、`C:/Users/mo/Documents/Codex/media-browser` 仅作参考，当前工作不修改它们。软路由 `/mnt/ssd/apps/peach` 未设独立 `HANDOVER.md`，本项目没有双端 `HANDOVER.md` 同步安排，软路由侧新增部署状态一并在本文件记录。

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
- 构建 47：普通 VLC 播放中的跳转以目标时间和新输出帧共同确认，失败时不记录未确认位置。失败页从头重试绕开本机和服务端续播点。详情刷新失败仍可用列表中的原作品进入播放器。主要文件为 PlaybackController.swift、VLCOriginalPlayer.swift、PlayerView.swift、ItemDetailView.swift。用户复测后 081 快进仍停在旧画面，331 仍不能起播。
- 构建 49：只改 `PeachTest/Core/VLCOriginalPlayer.swift`，且只作用于 `PlayerView(item:api:)` 的普通播放器。跳转前冲刷 VLC 的 sample-buffer 画面层；该层失败时继续冲刷，直到新帧被接受或原有超时结束。失败页增加调用耗时、媒体时间、读取/解码/显示计数和画面层状态。不改时钟、缓存、解码器、手势、播放墙和小窗控制器。播放墙、随机连播和预览仍走默认播放器。
- 构建 49 云端 iPhone ARM64 Release 编译及 IPA 校验通过。本机不能编译 iOS，也没有跑模拟器。证据在 artifacts/codemagic-49/。构建 47 的证据仍在 artifacts/codemagic-47/。馆藏数量会随用户维护变化，不沿用历史 54 部作为当前事实。
- 构建 50（`438edb1`）：针对普通 VLC 播放器（`VLCOriginalPlayer` 与 `PreviewFilmstrip`）调整 4K MKV 起播/首帧判断与跳转确认容差（基于 `origin`），增加 `:input-fast-seek` 与 `:network-caching=300` 选项，并尝试在普通倍速切换时冲刷画面层。用户真机实测退出播放器后 App 卡死（回归原因：`VLCPlayerRetirement` 在主线程监听 `.main` 队列退出）。
- 构建 51（`e4c1634`）：修复构建 50 退出播放器后卡死回归——将 `VLCPlayerRetirement` 状态监听与 5 秒超时回收迁移到独立后台串行 `DispatchQueue("Peach.VLC.retirement")`，避免主线程阻塞，并去掉伪造 `AVAudioSession.routeChangeNotification`。
- 构建 52（`a300217`）：
  1. **完整运行日志系统**：新增 `PeachLogRedactor`、`PeachLogFormatting`、`PeachRuntimeLogger`（`PeachLogStore` 落盘 `ios-runtime.jsonl`，`3600` 秒本地保留，`NWPathMonitor` 断网恢复后仅补传未过期日志，按条目 ID 幂等去重，后台每 3 秒批量上传且不阻塞播放与 UI）与 `AppLogsView`（「我的 → 日志」，显示本机与软路由最后一次上传响应返回的实际字节数，未获取时显示 `"暂未获取"`）；接入 `VLCPrivateLogSink`（level 3 全级别 + `VLCLogContext`）与 `AVPlayer`/`AVPlayerLayer`/`AVAudioSession`/PiP 及各业务模块诊断日志。
  2. **软路由日志接收与清理（`192.168.5.5`）**：部署 `peach-edge` 与 `peach-log-receiver`，通过带会话 Cookie 认证的 `POST /api/ios-logs` 二次脱敏后追加写入 `/mnt/ssd/apps/peach/ios-playback.jsonl`，后台 `30s` 线程 + 宿主机 `*/5 * * * *` cron 定时清理超过 1 小时记录；`192.168.5.5:8900/healthz` 返回 `200`，未认证 `POST /api/ios-logs` 返回 `401`。`2026-11-14 08:45` 已观测 `/mnt/ssd/apps/peach/ios-playback.jsonl` 写入 `8,372,174` 字节（表明已有真机上传运行），尚未取得完整真机人工验收反馈。
  3. **大图模式自动预览**：`DwellSelection` 调整为连续停留 `1.0` 秒触发自动预览（原 3 秒）；`LibraryRootView` 在当前预览卡片封面可见比例 ≥65% 时保持播放不中断；`PlaybackController` 与 `VLCOriginalPlayer` 对 `previewOnly` 强制静音（`:no-audio` + `isMuted = true` + `volume = 0`）。
  4. **已验证测试与构建范围**：Windows Swift 6.4.2 Release 执行 `swift test --configuration release` 运行 `55` 项：通过 `51` 项（含 `RuntimeLoggingTests` 4 项、`WallPreviewTests` 7 项），跳过 `4` 项（live Peach / 本地 HTTP Cookie fixture），`0` 失败（`OriginalPlaybackTests` `#if canImport(AVFoundation)` 测试在 Windows 未编译）；Codemagic 构建 52（`6af78987638832d0f45cf595`）`scripts/build-unsigned-ipa.sh` 整步 `success`（依次包含 macOS `swift test`、Release 编译、`** BUILD SUCCEEDED **` 与 `ipa-validation.json` 通过）；未运行模拟器测试。
- **构建 53–56（普通 VLC 播放器 `:clock-master=input` + `VLCAVSampleAudioSyncBridge`，当前稳定构建 56）**：
  1. 构建 53（`7de427c`）仅对 `PlayerView` 普通 VLC（`confirmsSeekFrames == true`）启用 `:clock-master=input`、`:input-fast-seek` 与 `:network-caching=300`，真机确认画面 `2×`/`1×` 切速延迟消失，但日志显示 `2×` 时因 `scaletempo` 输出与 `dec.c` 缓冲估算时钟基准错配触发大量 `playing silence` 与 `down-sampling`，恢复 `1×` 时触发 `flushing buffers` 与滞后。构建 54（`0ed00fd`）单变量验证 `--no-audio-time-stretch` 无改善并已在后续撤回。
  2. 构建 56（`24cddcc`，含实现提交 `0e2639b`）仅修改 `PeachTest/Core/VLCOriginalPlayer.swift`：撤销 `--no-audio-time-stretch` 并恢复共享 `VLCMediaPlayer()`，保留 `:clock-master=input`，在应用层新增 `VLCAVSampleAudioSyncBridge`（动态校验 `VLCAVSample` Objective-C ivar 并以 `Lease` 与 `input` 主时钟判定隔离普通播放器范围）：在 `whenTimeObserved:` 与 `play:date:` 清除 `rate_system_ts`/`rate_audio_ts` 覆盖、按 `writtenUs - round(remainingHwUs * syncRate)` 补偿上调时间戳，并通过 `willChangeRate(to:)` 在切速过渡期（最多 250ms）清零 `system_ts` 避免跨速单包误判冲刷或插静音。
  3. **已验证范围（构建 56）**：Windows Swift 6.4.2 Debug/Release 执行 `swift test` 与 `swift test --configuration release` 均 `55` 项运行、`51` 通过、`4` 跳过、`0` 失败；Codemagic 构建 56（`6af86196cd5a07c6844f96b0`）通过编译与 IPA 校验，交付包已由用户确认作为当前稳定构建。

## 当前稳定备份

- **当前稳定构建：构建 56（提交 `24cddcc351a55acba5128a5d7c8bc5b6d1f4031c`，Codemagic `6af86196cd5a07c6844f96b0`）。** IPA 交付于 `C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.56.ipa`（SHA256 `37f360f0507f8bbbb21e22224b4d497dc3be23de651865999e1c9ee7926be63b`），对应稳定源码与元数据备份存于 `backups/stable-build56-20261114-214500/`，云端产物与本地校验留存于 `artifacts/codemagic-56/`。
- 历史对照基线保留：`Peach-iOS-Test-unsigned.53.ipa`（`:clock-master=input` 未修音频对照）、`Peach-iOS-Test-unsigned.52.ipa`、`NAS-unsigned .51.ipa`（退出回收修复基线）及构建 46 IPA（音频主时钟旧基线，存在 2× 约 1 秒延迟）。
- 构建 38（`207c3385dcc8d44da0dace2a02037a14d0960693`）`clock-master=monotonic` 导致卡死/无声/掉帧，构建 50 存在退出播放器卡死回归，构建 54 `--no-audio-time-stretch` 无效并已撤回；**均勿再用作基准**。
- 既有源码与交接备份保留（当前共 `13` 份目录，未超 `15` 份普通备份上限，且 `stable-build56-20261114-214500/` 为指定稳定备份需长期保留）：`backups/stable-build56-20261114-214500/`（构建 56 稳定源码包、`VLCOriginalPlayer.swift`、`HANDOVER.md.bak`、`commit.txt`、`manifest.txt`）、`backups/vlc-audio-sync-20261114-210248/`、`backups/vlc-no-timestretch-20261114-202157/`、`backups/vlc-clock-input-20261114-194108/`、`backups/handover-20261114-093200/`、`backups/preview-player-20261109-030505/source.zip`（`0c972b1`）、`backups/local-preview-decode-20261108-041442/source.bundle`（`02bd7ee`）、`backups/vlc-pip-20261108-001740/source.bundle`（`d163e33`）及其他早期备份；实测运行日志留存于 `artifacts/ios-playback.jsonl`。
- NAS 构建 82 及原工程未在本轮修改或重打包。

## 必须遵守的规则

- 权威规则：本项目 `AGENTS.md`、`C:/Users/mo/.codex/AGENTS.md`、`C:/Users/mo/.codex/instructions/git-safety.md`、`C:/Users/mo/.codex/instructions/recovery-handover.md`、`C:/Users/mo/.gemini/antigravity/AGENTS.md`（若需 Antigravity 宿主自动注入，应同时维护于 `C:/Users/mo/.gemini/GEMINI.md`）。工作区未跟踪的 `AGENTS.md`、`D ACCEPTANCE.md` 与 SwiftPM 生成的 `Info.plist` 不混入代码提交。
- 只改独立 Peach App 及本轮显式授权的软路由日志接收与清理组件；不接入 NAS iOS，不修改 Peach 主业务服务、源媒体与 NAS 工程，不改播放墙内嵌播放器；不得新增公网端口。
- 仅手动触发 Codemagic `ios-unsigned-ipa`；同一提交/工作流已有构建不重复启动，**不为纯文档（`HANDOVER.md`）更新触发构建**；GitHub Actions 保持禁用；未经明确授权不启动 Simulator。
- iPhone 真机反馈才是播放、手势、日志链路和自动预览的最终验收结论。提交前须复核 staged diff 与旧功能回归；不得覆盖已有 Downloads 同名文件（如 `NAS-unsigned .52.ipa`、`NAS-unsigned .56.ipa`），必须先核对 SHA256。

## 未解决问题

- **构建 50–52 真机完整回归与单项确认尚未收到用户全部书面回执（其中构建 56 已由用户确认作为当前稳定构建）**：
  - 4K MKV `SONE-081` 起播/多次快进出画/退出重开、`START-331` 首帧起播、退出播放器不卡死（构建 51 修复）及系统小窗回归以真机连续使用观察为准。
  - 若后续升级 CocoaPods 中 `VLCKit`（当前为 `4.0.0a25`），需重新核对 `VLCAVSampleAudioSyncBridge` 依赖的 `vlc_aout_stream` / `vlc_clock_main_t` C 结构体偏移。
  - 大图模式连续停留 **1 秒**自动预览、全程**强制静音**及封面 **≥65% 持续播放**需在真机持续回归中核对。
  - 运行日志系统、断网补传、App「我的 → 日志」字节/时间显示与软路由 `/mnt/ssd/apps/peach/ios-playback.jsonl` 1 小时自动清理效果待长时观察。
- 快拖进度条黑图、详情原图预缓存后偶发转圈、拖进度画面静止等历史已改项仍缺完整逐项真机通过回执。
- 播放列表改名/删除/排序、部分管理写操作和照片墙等未完成范围见 `FEATURE-MATRIX.md`。

## 下一步任务

1. 日常真机回归与后续迭代均以稳定版本 **构建 56**（`C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.56.ipa`，提交 `24cddcc`；切勿误用旧 `NAS-unsigned .56.ipa`）为基准；必要时可结合 `/mnt/ssd/apps/peach/ios-playback.jsonl` 或本地 `artifacts/ios-playback.jsonl` 核对 `Audio sync compensated` / `Audio sync restored 1.0x` 与音频告警计数。
2. 如需在未来开发前保留或恢复稳定基线，优先从 `backups/stable-build56-20261114-214500/` 或提交 `24cddcc351a55acba5128a5d7c8bc5b6d1f4031c` 切出，不要用普通备份轮转删掉 `stable-build56-20261114-214500/`。
3. 如需后续 Antigravity 新会话自动加载全局规则，将 `C:/Users/mo/.gemini/antigravity/AGENTS.md` 同步到 `C:/Users/mo/.gemini/GEMINI.md`。
4. 仅在取得新缺陷诊断或新用户需求后，先按 `backups/<任务名>-YYYYMMDD-HHMMSS` 备份再修改代码、复核 staged diff 并触发后续构建。
