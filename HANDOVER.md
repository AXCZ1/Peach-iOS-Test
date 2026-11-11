# Peach iOS Test 当前交接

更新日期：2026-11-11。最新交付为独立 Peach App **构建 44**；已编译、打包、校验并交付，**尚未收到构建 44 的 iPhone 实测结果**。用户已反馈构建 43：长按 2× 的开始和结束都大约延迟一秒。构建 41 的反馈仍然有效：比构建 40 好一些，但仍约一半次数触发，且开始 2× 时会跳帧。

## 当前项目路径和运行方式

- 【PC PowerShell｜项目目录 `C:/Users/mo/Documents/Codex/Peach-iOS-Test`】独立 SwiftUI 项目，仓库 https://github.com/AXCZ1/Peach-iOS-Test，分支 `main`。
- 构建 44 源码：`383762379e36abf445a823f081b89961a526e728`，已推送。Codemagic 构建 ID：`6af48640550a6a541e5cc5ff`，状态 finished。构建 43 源码仍是 `272ff0573f9b88bbd2a85147243ae3cacce9bf7d`，Codemagic `6af4780aa53ea1f2894b7998`。
- IPA：`C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.44.ipa`，21,125,242 字节；SHA256 `8f2ae974a0b8377c6cb7e38749d97e51efaa5295d681bf3db5de4633e67f3036`。同号 `NAS-unsigned .44.ipa` 已存在且哈希不同（2,699,441 字节，SHA256 `187edf921c8b3ad9f7fb4287114be7152d7bbf5668d844cf80be4da07abed92e`），保留未覆盖。构建 43 的 IPA 仍在 `C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.43.ipa`。
- Bundle ID `com.axcz1.peachios.test`，显示名 `Peach Test`，iOS 17.0+，iPhone ARM64，无签名；安装仍用用户现有签名方式。
- `codemagic.yaml` 的 `ios-unsigned-ipa` 调用 `scripts/build-unsigned-ipa.sh`；Pod 安装后使用 `PeachTest.xcworkspace` / `PeachTest` scheme。Codemagic 应用 ID `6aed85f0165a22c4d4b043a0`。API 凭据由进程环境提供，不写入仓库。
- 后端为用户自管 Peach 0.52.0；App 支持局域网地址和 HTTPS 域名，登录态及密码保存在设备。馆藏数量会变化，不沿用历史 54 部作为当前事实。本轮未重新探测后端。
- `C:/Users/mo/Documents/Codex/NAS-ios`、`C:/Users/mo/Documents/Codex/media-browser` 仅作参考，当前工作不修改它们。本项目没有需要同步软路由 HANDOVER 的既定双端安排。

## 当前功能状态

- 独立 App 已有馆藏、索引/分类、搜索与历史、筛选与排序记忆、详情、个人记录、随机连播、播放墙和系统小窗；管理入口以只读状态为主。功能清单参考 `FEATURE-MATRIX.md`，其中验收状态可能落后于最新代码。
- 原文件在 iPhone 上由 AVPlayer 或 VLCKit 4.0.0a25 解码，正式播放不回退 NAS HLS 转码。VLC 无首帧且已收到数据时可用软件解码重试一次；这不代表所有作品已能播放。
- 两套图片缓存必须区分：详情阅览图使用 `OfflinePreviews` 原尺寸 PNG，支持手动整库扫描、续做和补缺；进度条使用 `MediaBrowserSeekClient` / `SeekPreviewCache` 提前同步 NAS 已生成的 WebP 小图。NAS 不打缩略图包；进度条缓存改动不应改变详情原图。
- 构建 34 将进度条小图同步改为受限滚动并发、App 生命周期持有任务，离开设置页仍可继续；iOS 后台暂停后回到 App 续做。构建 36 合并快速拖动的缩略图请求并提前加载图库相邻原图。历史证据参考 `ACCEPTANCE.md`、对应提交及 `artifacts/codemagic-*/`，不能仅凭实现认定真机问题已消失。
- 普通播放手势：左右各 25% 双击 ±10 秒，中央双击播放/暂停；同侧每次有效快进/退后重新开放 700ms 单击续窗。提示按实际累计位移显示 `+10 / +20 / +30` 或负数，已去掉快进/退图标；播放/暂停白色图标保留，暂停时常驻。
- 普通画面横滑跨度是全宽对应片长的 0.05；拖动时维持原播放/暂停状态，松手提交 seek。长按识别为 250ms，按下请求 2×、松手恢复 1×。播放墙的既有手势和内嵌播放器不套用普通播放器改动。
- 构建 40 的定向修改：撤回构建 38 的 `clock-master=monotonic`，恢复 VLC 默认音频主时钟；仅 `PlayerView(item:api:)` 创建的普通播放器通过工厂启用 `interactivePlayback: true`，设置 `network-caching=300`（默认原为 1000ms）。保留自适应 jitter，不在切速时强制 seek、暂停或重建。播放墙、随机连播、卡片预览仍用默认配置。用户随后报告长按 2× 仍有掉帧、延迟和卡死。
- 构建 41 只改 `PeachTest/Core/VLCOriginalPlayer.swift` 的普通播放器媒体选项：保留 `network-caching=300`，增加 `clock-jitter=0` 和 `no-audio-time-stretch`。Pod 名是 VLCKit 4.0.0a25，但设备二进制版本字符串是 libVLC 3.0.23，其中没有 `clock-master`，所以构建 38 的 monotonic 选项不会被读取。3.0.23 在 PCR 迟到且未超过 `clock-jitter` 时走 `ES_OUT_RESET_PCR` 并重新缓冲。按住 2× 期间音调会升高。播放墙、沉浸页和预览没有这条入口。用户随后反馈好了一些，但仍约一半次数触发，且开始 2× 会跳帧。
- 构建 43 仍只改这个文件的普通播放器。保留 `clock-jitter=0` 和 `no-audio-time-stretch`。`network-caching` 从 300 改为 150。3.0.23 的显示时间偏移是缓存乘以 (1/速度 − 1)；300ms 下 1×→2× 一次跳 −150ms，超过 2× 音频冲刷阈值（约 90ms），并让视频输出裁掉日期不早于新帧的队列，这就是开始倍速时的跳帧。150ms 把整段偏移压到 75ms。已经在播放时，倒数速率按 0.1 逐级变化（一级约 15ms，级间 50ms，1× 到 2× 约 200ms）。libVLC 会把连续的变速控制收成最后一次，所以不能在一帧之内设到底。暂停、停止和第一次播放仍立即设速，不 seek、不重建。播放墙、沉浸页和预览不走这条入口。用户随后反馈：开始和结束都大约延迟一秒。逐级变化停在冲刷阈值以下，设备里已经转换好的旧声音会按原速播完。
- 构建 44 仍只改这个文件的普通播放器。保留 `clock-jitter=0` 和 `no-audio-time-stretch`。去掉逐级变速，播放中也立刻设置速率。`network-caching` 从 150 改为 220。220ms 下 1×→2× 的显示时间大约提前 110ms，超过 2× 音频冲刷阈值（约 90ms），按下时应丢掉已转换的旧声音。2×→1× 大约推后 110ms，低于 1× 插入静音的阈值（约 120ms）。减速不会清空设备缓冲；如果按住期间缓冲又被填满，松手仍可能要等它播完。开始时画面可能仍有大约 110ms 的跳动，应小于构建 41 的约 150ms。不 seek、不暂停、不重建。播放墙、沉浸页和预览不走这条入口。按住期间音调升高仍是预期。
- 涉及文件：`PeachTest/Core/VLCOriginalPlayer.swift`。700ms 规则仍在 `PeachTest/Core/MediaPresentation.swift`，本轮未改。
- 验证：构建 44 工作流里 Debug 与 Release 各 65 项测试、4 项跳过、0 失败；iPhone ARM64 Release `BUILD SUCCEEDED`。本地核对 ZIP、Info.plist、ARM64、无签名和 SHA256。证据在 `artifacts/codemagic-44/`。构建 43 的同类云端结果仍在 `artifacts/codemagic-43/`。未启动模拟器，未实测真机倍速。
- `ACCEPTANCE.md` 首节目前仍为构建 34，不能当作构建 40 的验收回执；本文件记录当前继续点，旧构建详情继续查原记录及 Git 历史。

## 当前稳定备份

- **没有已确认消除倍速问题的稳定版本。** 构建 37 的 IPA 仍在 Downloads，源码 `d544e7a1b160a8523a2e63bfa4ef393ff1b7fb29`；用户已报告 VLC 实际切速和松手恢复各延迟约 1–2 秒，只能作为回归前比较点，不能称为无缺陷稳定版。
- 构建 38（`207c3385dcc8d44da0dace2a02037a14d0960693`）强改时钟后，用户报告卡死、无声、声音卡住和掉帧；**不要恢复该时钟方案，也不要推荐构建 38 回退**。
- 构建 39（`37eff0c87bbeee3bd3421dc0c9bc4f1b4fe3d12b`，Codemagic `6af409e2785c68ee929f4ccb`）只撤回时钟并删快进图标，云端成功但未作为最终修复交付；用户明确不接受仅回退旧状态作为解决方案。当前继续点是构建 44。构建 43 被用户评为开始和结束都大约延迟一秒。构建 41 只被用户评为好了一些，约一半次数仍会触发，开始 2× 仍跳帧。构建 40 的真机问题尚未被新包证实消除。
- 既有源码备份保留：`backups/preview-player-20261109-030505/source.zip`（`0c972b1`）、`backups/local-preview-decode-20261108-041442/source.bundle`（`02bd7ee`）、`backups/vlc-pip-20261108-001740/source.bundle`（`d163e33`）及其他历史备份。它们只覆盖源码，不代表后端或媒体备份；本轮不新增或清理备份。
- NAS 构建 82 和原工程未在本轮修改或重新打包；历史校验见 `ACCEPTANCE.md`。本轮未重复验证其文件哈希。

## 必须遵守的规则

- 权威规则：本项目 `AGENTS.md`、`C:/Users/mo/.codex/instructions/git-safety.md`、`C:/Users/mo/.codex/instructions/recovery-handover.md`。工作区 `AGENTS.md` 是用户提供的未跟踪文件，保留，不混入交接或代码提交。
- 只改独立 Peach App；用户已决定不接入 NAS iOS。域名用户自行配置，不修改服务端、源媒体、NAS 项目、自动采集或播放墙内嵌播放器。
- 仅手动触发 Codemagic `ios-unsigned-ipa`；同一提交/工作流已有构建不重复启动，不为文档构建。GitHub Actions 保持禁用；未经明确授权不启动 Simulator。
- iPhone 真机反馈才是播放和手势验收结论。编译、API 成功、纯逻辑测试都不能证明 VLC 音画已恢复正常。限定修改范围，检查共享组件调用方，不借机改缓存、布局或其他播放器。
- 当前代码提交已在远程；仅为实际交接整理并提交 HANDOVER。不得覆盖已有 Downloads 同名文件，必须先核对哈希。

## 未解决问题

- **首要问题：VLC 长按 2×及松手后的真实音画响应。** 用户在构建 43 上反馈：开始和结束都大约延迟一秒。构建 41 的反馈仍然有效：好了一些，但仍约 50% 触发，且开始倍速时会跳帧。2× 提示及时，延迟的是画面速度；解码显示「原文件直放 · VLC」或「VLC 软件解码」。不要再次把问题当作长按识别延迟，也不要重复询问这两个已确认事实。构建 44 尚未收到真机结果。
- 构建 41 的判断依据是设备二进制里的 libVLC 3.0.23 字符串，以及与之对应的 3.0.23 `es_out.c` 和 `clock.c`：迟到 PCR 在默认 jitter 内会重新缓冲；`ClockGetTsOffset` 使 2× 的显示时间相对 1× 提前半个缓存。这不是手机测量。`clock-jitter=0` 会改变普通播放器在 1× 迟到时的处理，从重新缓冲改为重置时钟；只在 PCR 迟到时出现。构建 44 没有取消这个行为。
- `artifacts/upstream/vlc-rate/` 来自较新的 VLC master，含 `clock-master`，**不等于**内嵌 3.0.23。不要再按那套主时钟源码改这个包。
- 历史 SONE-081 在构建 27 仍黑屏，用户没有给出后续解决回执；构建 40 未修这个单片问题。
- 快拖进度条黑图、详情原图预缓存后偶发转圈、拖进度画面静止均已有定向改动，但本会话没有收到完整真机通过回执；不要将旧未确认问题一并宣称解决。
- 播放列表改名/删除/排序、部分管理写操作和照片墙等未完成范围参考 `FEATURE-MATRIX.md`，不属于当前倍速修复任务。

## 下一步任务

1. 用构建 44 在同一部原先出问题的作品上短按住、持续按住、反复按住和松手。分别看按下后画面变快要多久，松开后回到 1× 要多久，以及开始时有没有小幅跳帧。按住期间音调升高是预期。不要把 2× 提示当成速度证据。
2. 若松手仍要大约一秒，而按下已经变快，说明减速没有清空设备缓冲，下一步再针对松手。不要再给这个 3.0.23 二进制加 `clock-master`，也不要把缓存改回 300 或恢复逐级变速当成修复。
3. 一并看快进累计秒数和 700ms 续点，以及普通拖动、暂停、退出和 PiP。播放墙内嵌播放器不应改变。
4. 只在有新的真机证据后再改代码和构建。
