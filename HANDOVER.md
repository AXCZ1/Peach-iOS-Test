# Peach iOS Test 当前交接

更新日期：2026-11-11。最新交付为独立 Peach App **构建 40**；已编译、打包、校验并交付，**尚未收到构建 40 的 iPhone 实测结果**。本次交接只整理文档，不重新构建。

## 当前项目路径和运行方式

- 【PC PowerShell｜项目目录 `C:/Users/mo/Documents/Codex/Peach-iOS-Test`】独立 SwiftUI 项目，仓库 https://github.com/AXCZ1/Peach-iOS-Test，分支 `main`。
- 构建 40 源码：`e998ee3333bb49a91a0bd654e9b782e76b63f728`，已推送；之后的交接文档提交不改变 IPA 内容。Codemagic 构建 ID：`6af40be5ee23c91ac258825d`，状态 finished。
- IPA：`C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.40.ipa`，21,125,409 字节；SHA256 `5216bea7f3f02cd98c930cc84ef043f0056753c1b27eca3ca6709aa096f23971`。同号 NAS 安装包已存在，保留未覆盖，因此使用 Peach 文件名。
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
- 构建 40 的定向修改：撤回构建 38 的 `clock-master=monotonic`，恢复 VLC 默认音频主时钟；仅 `PlayerView(item:api:)` 创建的普通播放器通过工厂启用 `interactivePlayback: true`，设置 `network-caching=300`（默认原为 1000ms）。保留自适应 jitter，不在切速时强制 seek、暂停或重建。播放墙、随机连播、卡片预览仍用默认配置。
- 涉及文件：`PeachTest/Core/PlaybackController.swift`（撤回时钟参数），`PeachTest/Core/VLCOriginalPlayer.swift`（默认时钟及普通播放缓冲），`PeachTest/Features/Player/PlayerView.swift`（定向入口和快进提示）。700ms 规则位于 `PeachTest/Core/MediaPresentation.swift`。
- 验证：本地 `MediaInteractionTests` 14 项通过；构建 40 工作流中的 Debug/Release 核心测试、iPhone ARM64 Release 编译及云端 IPA 校验成功。本地重新核对 ZIP、Info.plist、ARM64、无签名和 SHA256。证据在 `artifacts/codemagic-40/ipa-validation.json`、`build-summary.txt`、`xcodebuild.log`。未启动模拟器，未实测真机倍速延迟。
- `ACCEPTANCE.md` 首节目前仍为构建 34，不能当作构建 40 的验收回执；本文件记录当前继续点，旧构建详情继续查原记录及 Git 历史。

## 当前稳定备份

- **没有已确认消除倍速问题的稳定版本。** 构建 37 的 IPA 仍在 Downloads，源码 `d544e7a1b160a8523a2e63bfa4ef393ff1b7fb29`；用户已报告 VLC 实际切速和松手恢复各延迟约 1–2 秒，只能作为回归前比较点，不能称为无缺陷稳定版。
- 构建 38（`207c3385dcc8d44da0dace2a02037a14d0960693`）强改时钟后，用户报告卡死、无声、声音卡住和掉帧；**不要恢复该时钟方案，也不要推荐构建 38 回退**。
- 构建 39（`37eff0c87bbeee3bd3421dc0c9bc4f1b4fe3d12b`，Codemagic `6af409e2785c68ee929f4ccb`）只撤回时钟并删快进图标，云端成功但未作为最终修复交付；用户明确不接受仅回退旧状态作为解决方案。当前继续点是构建 40。
- 既有源码备份保留：`backups/preview-player-20261109-030505/source.zip`（`0c972b1`）、`backups/local-preview-decode-20261108-041442/source.bundle`（`02bd7ee`）、`backups/vlc-pip-20261108-001740/source.bundle`（`d163e33`）及其他历史备份。它们只覆盖源码，不代表后端或媒体备份；本轮不新增或清理备份。
- NAS 构建 82 和原工程未在本轮修改或重新打包；历史校验见 `ACCEPTANCE.md`。本轮未重复验证其文件哈希。

## 必须遵守的规则

- 权威规则：本项目 `AGENTS.md`、`C:/Users/mo/.codex/instructions/git-safety.md`、`C:/Users/mo/.codex/instructions/recovery-handover.md`。工作区 `AGENTS.md` 是用户提供的未跟踪文件，保留，不混入交接或代码提交。
- 只改独立 Peach App；用户已决定不接入 NAS iOS。域名用户自行配置，不修改服务端、源媒体、NAS 项目、自动采集或播放墙内嵌播放器。
- 仅手动触发 Codemagic `ios-unsigned-ipa`；同一提交/工作流已有构建不重复启动，不为文档构建。GitHub Actions 保持禁用；未经明确授权不启动 Simulator。
- iPhone 真机反馈才是播放和手势验收结论。编译、API 成功、纯逻辑测试都不能证明 VLC 音画已恢复正常。限定修改范围，检查共享组件调用方，不借机改缓存、布局或其他播放器。
- 当前代码提交已在远程；仅为实际交接整理并提交 HANDOVER。不得覆盖已有 Downloads 同名文件，必须先核对哈希。

## 未解决问题

- **首要问题：VLC 长按 2×及松手后的真实音画响应。** 用户明确说 2× 提示及时，延迟的是画面速度；解码显示「原文件直放 · VLC」或「VLC 软件解码」。不要再次把问题当作长按识别延迟，也不要重复询问这两个已确认事实。
- 构建 40 的 300ms 缓冲旨在缩短旧速率音频队列的等待；依据来自 VLC HTTP PTS delay、音频输出排队及切速源码，不是手机测量。尚不能确认卡死、无声、掉帧及 1–2 秒延迟已解决；较短缓冲在网络抖动时的表现也未实测。
- 本地源代码调查在 `artifacts/upstream/vlc-rate/`，来自 VideoLAN 上游 master，**不保证等于内嵌 4.0.0a25 的准确源码版本**；只确认内嵌 iOS 二进制包含 `network-caching` 选项。继续定位应优先采集实际播放证据，避免再凭通用源码推测修改音画时钟。
- 历史 SONE-081 在构建 27 仍黑屏，用户没有给出后续解决回执；构建 40 未修这个单片问题。
- 快拖进度条黑图、详情原图预缓存后偶发转圈、拖进度画面静止均已有定向改动，但本会话没有收到完整真机通过回执；不要将旧未确认问题一并宣称解决。
- 播放列表改名/删除/排序、部分管理写操作和照片墙等未完成范围参考 `FEATURE-MATRIX.md`，不属于当前倍速修复任务。

## 下一步任务

1. 以构建 40 的真机反馈继续：同一出现问题的作品分别短按住、持续按住及反复按住/松手，检查实际音画进入 2×、恢复 1×的时间，以及卡顿、无声和掉帧。不要把提示响应当作播放速度证据。
2. 若仍失败，针对 VLC 输入缓冲、音频输出排队及实际播放时间推进可复现诊断；分清事实、推断和待测项。仅回退、调识别时间或再强改时钟都不能当作完整修复交付。
3. 一并检查快进仅显示真实累计秒数，每次快进后的 700ms 均可续点；回归普通拖动、暂停、退出和 PiP，保持播放墙内嵌行为。
4. 只在确有代码修改和相关检查后再构建。当前整理交接不触发新 IPA、不操作生产或 NAS。
