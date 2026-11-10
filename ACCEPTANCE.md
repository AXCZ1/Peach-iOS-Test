# 构建 32 · 进度条缩略图提前缓存

独立安装包为 [Peach-iOS-Test-unsigned.32.ipa](C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.32.ipa)，21,098,777 字节，SHA256 `f59871a956cb14ade1817b8e72014f2acc8f8cd7695e071e6d4d217bc761f3e8`。源码 `4b624c85dd407e750362cd5c4c2fbfe6b7f1d15a`，Codemagic `6af2b59cb6563a81b57c1899`。iPhone ARM64 Release 编译和两端 IPA 校验通过；保留 Downloads 中已有的同号 NAS 安装包。校验和编译日志在 `artifacts/codemagic-32/`。

真机待验收。在「我的 → 进度条缩略图」填写 Media Browser 的 HTTPS 地址和密码，在 Wi-Fi 下让 App 同步尚未打开的作品。确认中断后续做、普通播放器和随机连播拖动时直接显示缓存小图，详情页阅览图与播放墙照旧。新片在两个馆藏均可找到、且 NAS 生成小图后，下次同步自动补齐；NAS 不打缩略图包。

# 构建 31 · 索引返回保留滚动位置

独立 Peach 安装包为 [NAS-unsigned .31.ipa](<C:/Users/mo/Downloads/NAS-unsigned .31.ipa>)，21,022,952 字节，SHA256 `390bec1a8d7231f06e04e152e034a829e05a6f15b2022e90fb9ab419d32020c6`。源码 `2a662f6738ca0809ec3e31a5cc9056457b3a3aea`，Codemagic `6af1fca97be2a39892c9a83f`。

`EntityBrowseView.swift` 让索引网格和分类内的作品列表在返回时复用已加载数据。已检查分类切换、提交搜索、下拉刷新及初次加载的代码路径。Debug 和 Release 各 56 项通过、4 项跳过，iPhone ARM64 Release 编译与 IPA 校验通过。

真机待验收。在索引中滚动到较靠后的分类，打开后再滚动到较靠后的作品。分别用返回按钮和侧滑从作品详情返回，确认作品列表位置保留，再退回索引确认分类网格的位置保留。最后复查分类切换、搜索和下拉刷新。

# 构建 30 · 整库原图扫描续做

独立安装包为 [Peach-iOS-Test-unsigned.30.ipa](C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.30.ipa)，21,022,277 字节，SHA256 `81b37f80ca54d85826df2c3830560d41b0d1ef337a14973d34f2c7e582bff34a`。源码 `55b4c2d8a76fc7ed4b3de0aed936ca973782a2fd`，Codemagic `6af16f297cd45783ed247d73`，验证记录见 `artifacts/codemagic-30/`。Downloads 中已有同号 NAS 文件，因此安装包使用 Peach 文件名。

`OfflinePreviewScan.swift` 显示当前作品和帧进度。连续两张取帧失败后，先处理下一部。`OfflinePreviews.swift` 保留已存原图并记录续扫位置。`OfflinePreviewTests.swift` 覆盖失败后续扫、已存帧复用，以及成功后重置连续失败计数。Debug 和 Release 各 56 项通过、4 项跳过，iPhone ARM64 Release 编译和 IPA 校验通过。

真机待验收。覆盖安装后打开「我的 → 本机缓存」扫描，确认已存原图可以复用，当前作品显示逐张进度。遇到连续失败的作品时确认会继续下一部，再开扫描确认可补缺。

# 构建 29：整库原图缓存与播放控制

独立安装包：[Peach-iOS-Test-unsigned.29.ipa](C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.29.ipa)，21,016,427 字节。SHA256 `39e49f86d4e39b7b2397564f9cf82ca29765419df3e5d654dfa4c9ca2890d62a`。无签名 iPhone ARM64、iOS 17.0+，Bundle ID `com.axcz1.peachios.test`。默认命名位置已有不同文件，未覆盖。源码 `9f1c3f2eeedb5b59e9734e5f959e48e1e75e0cb6`；Codemagic `6af0cbeaa1b4111a0a6c3413`，日志和本地校验见 `artifacts/codemagic-29/`。

| 改动 | 文件 |
| --- | --- |
| 手动整库缓存，续做、跳过和孤儿清理；详情优先使用同一份原图 | OfflinePreviews.swift、MediaDiskCache.swift、OfflinePreviewScan.swift、AccountHubView.swift、PeachTestApp.swift、PreviewFilmstrip.swift |
| 普通播放器与随机连播的进度预览复用原图 | MediaArtwork.swift、PlayerView.swift、ImmersiveView.swift |
| 相册与普通竖屏播放下滑返回，随机连播分页与横屏定位 | PreviewFilmstrip.swift、MediaGestureOverlay.swift、PlayerView.swift、ImmersiveView.swift、PlaybackOrientation.swift |
| 馆藏排序和方向记忆，取消不保存 | LibraryModel.swift、FilterSheet.swift |
| 原生计数写入和撤销，按时间打点 | PeachAPI.swift、PlaybackController.swift、ClimaxMarks.swift、MediaArtwork.swift、PlayerView.swift、ImmersiveView.swift |

验证：Mac Debug/Release 各 55 通过、4 跳过，iPhone ARM64 Release 编译成功。PC 独立校验了 Mach-O、IPA 结构、Bundle ID 和 SHA256。WSL 的 42 项测试通过，含 OfflinePreviewTests.swift 的采样、分页、孤儿清理、续做和版本失效，以及 LivePeachTests.swift 使用真实隔离 Peach 的反代测试：带不匹配 Origin 的请求返回 403，匿名原生请求返回 401，已认证原生请求记录和撤销均返回 200，本机时间点同步新增和移除，隔离计数恢复原值。针对 Mac 的目录比较修正后，WSL 重跑三项缓存测试通过。GitHub Actions 仍禁用。

真机待验收：

1. 在「我的 → 本机缓存」打开扫描；试中途取消或切到后台再回前台。完成后打开 MP4、MKV 详情，确认图已在本机，点开放大同一帧，未放大时可下滑返回、放大后下滑能移动图。
2. 重扫确认已完成作品跳过，新增作品补缓存；普通播放器拖动进度确认使用缓存原图，未缓存只显示时间。
3. 选择非默认排序和方向，重开 App、清除筛选确认保留；打开随机连播翻页，确认停住后不露出下一页；按全屏来回切换时作品、进度和声音不变。
4. 普通播放器和随机连播播放到明显时间点后记录一次，点小点跳回该时间，重开仍在；撤销移除对应小点。复核普通竖屏下滑关闭及既有横拖、双击、倍速、播放墙内嵌手势。未安装到 iPhone、未使用模拟器；SONE-081 正式播放黑屏不在这轮修复范围。

# Peach iOS Test — 构建 27 验收

安装包：[Peach-iOS-Test-unsigned.27.ipa](C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.27.ipa)，20,917,350 字节，无签名 iPhone ARM64，iOS 17.0+。SHA256 `8f93c70a5b84d87e599b0a0c92ac98f229a2315c5e5a335fb62fbe54e00d3407`。源码 `9f81cd04eaa3207cccbc1e2c6700f186c5321878`；Codemagic `6aefe2910e0f7ecdb5f76a2b`。本机校验和云端日志见 `artifacts/codemagic-27/`。

- SONE-081 真机症状：播放页打开，但未出首帧。该文件为 3840×2160、59.94 fps H.264/AAC MKV。只读核对原文件头、中、尾均为 HTTP 206；电脑走同一 HTTPS 域名解出前 120 帧，无解码错误。没有手机 VLC 的原始失败日志。
- `LocalOriginalPlayer.swift`、`VLCOriginalPlayer.swift`、`PlaybackController.swift`：正式播放已读到媒体数据却没有首帧时，用同一原文件在 iPhone 上切换软件解码一次，保留续播和静音状态。失败时结束加载并显示错误。成功起播、播放墙控件、详情预取和服务端配置沿用原行为。
- `OriginalPlaybackTests.swift`、`PlaybackLifecycleTests.swift`：覆盖同一票和会话、续播位置、单次重试、无首帧不记观看、网络失败不换解码器；原文件播放、画中画会话和预览回归随工作流运行。Debug/Release 各 52 通过、3 跳过；iPhone Release 编译和本机 IPA 校验通过。

真机待验收：覆盖安装后，从详情播放 SONE-081。若第一次没有画面，观察标题下方是否出现「原文件直放 · VLC 软件解码」，随后确认画面和声音。如仍失败，记下错误文字。再从播放墙试同一部，回归一部原先正常播放的影片。构建 26 保留回退。

---

# Peach iOS Test — 构建 26 验收

安装包：[Peach-iOS-Test-unsigned.26.ipa](C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.26.ipa)，20,916,539 字节，无签名 iPhone ARM64，iOS 17.0+。SHA256 `c7891cca8b57731240a605a7a9b6576b8fe5b561018a1db22b95716d55dd749d`。源码 `9736b8818d1b184d04769a60b1c0c32f14425407`；Codemagic `6aef8a454b804ab4e2e0ea3a`。本机校验和云端日志见 `artifacts/codemagic-26/`。

- `PreviewFilmstrip.swift`：详情打开预取前四张，横滑时预取后面两张，优先读取本机缓存。取到一张即显示，点开复用同一张原图。退出详情或开始播放时停止预取。
- `OriginalVideoFrame.swift`、`VLCOriginalPlayer.swift`：详情使用 iPhone 的 AVFoundation 或 VLCKit 从原文件取帧，按原分辨率缓存。升级后首次读取会从原文件重建帧缓存，旧帧随原有上限回收。
- `PlaybackController.swift`、`PreviewVideoSample.swift`、`PeachAPI.swift`、`PeachModels.swift`：大图静音片段改走原文件，保留停留触发和分段规则，移除旧转码流入口。普通播放、沉浸和播放墙沿用现有原文件播放和交互。
- `OriginalPlaybackTests.swift`、`OriginalVideoFrameTests.swift`、`Fixtures/original-playback-http.py`：HTTP Range 样本验证两张详情帧复用原文件票、保持 1920×1080；验证静音预览按采样位置读取原文件且不写观看记录，覆盖 MKV 的本机解码器路由。Debug/Release 各 51 通过、3 跳过；iPhone Release 编译、IPA 结构与哈希校验通过。

真机待验收：打开一部 MP4 和一部 MKV 的详情，稍等后滚到预览条，确认前几张已加载；向右滑、点开放大，再退出重进验证命中缓存。在大图停留约 3 秒验证静音短片和离开后恢复封面，回归普通播放、沉浸、播放墙和小窗。Mac 测试覆盖了本机解码器路由；iPhone 的 VLC 实际取帧、冷缓存速度待真机确认。

---

# Peach iOS Test — 构建 23 验收

安装包：[Peach-iOS-Test-unsigned.23.ipa](C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.23.ipa)，20,910,770 字节，无签名 iPhone ARM64，iOS 17.0+。SHA256 `7a52640fc08e05f4e80c953600e58d2ef06c1ec700602405ee443529d89b92b5`。源码 `1295a997a54de644859dac3e61129be533512b7c`；Codemagic `6aef7ac245a3d9dc5191530e`。校验和日志见 `artifacts/codemagic-23/`。

- `PlayerView.swift`：普通播放器中，同一横拖距离对应的时间偏移减半，拖动预览和松手跳转一致。进度条、沉浸模式、播放墙和小窗沿用既有行为。
- `PreviewFilmstrip.swift`：详情条按原采样时间逐张加载可见原画，先读既有缓存；点开直接放大已显示的同一帧。大图视频预览和播放进度条缩略图未改。
- Codemagic Debug/Release 各 49 通过、3 跳过，涵盖原尺寸帧读取与拖动后播放状态恢复；iPhone Release 编译及本机 IPA 校验通过。

真机待验收：同一部片横拖约五分之一屏宽，目标应移动约十分之一片长；播放墙仍只用原进度条。滚到详情预览条并横滑，确认点开前已出原图，点开可直接缩放。构建 22 保留回退。

---

# Peach iOS Test — 构建 22 验收

安装包：[Peach-iOS-Test-unsigned.22.ipa](C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.22.ipa)，20,899,961 字节，无签名 iPhone ARM64，iOS 17.0+。SHA256 `1148d4fb611c49420591f09099e2b639be2f249ef1797f59161336a8df281d4a`。源码 `4c4644f9a1bdf3766992f923cb86a07eef23c4fd`；Codemagic `6aef74cea3dc1d99849ebb15`。本机校验与云端日志见 `artifacts/codemagic-22/`。

- `VLCOriginalPlayer.swift`、`PlayerPresentation.swift`、`PlaybackController.swift`：用 VLCKit 4.0.0a25 的现有画面接入系统小窗，使用同一个原文件会话和播放位置；接入系统暂停、继续、跳转、退出及返回全屏。AVPlayer 保留原小窗入口。
- `PlayerView.swift`、`VideoWallView.swift`：普通播放器左右拖动画面，从当前进度预览目标时间及已有缩略图，松手跳转；播放墙及其全屏和小窗返回页均不启用此手势，仍可操作原进度条。沉浸模式沿用既有手势。
- `Podfile`、`Podfile.lock`、`ThirdPartyNotices.txt`、`verify-ipa.py`：固定官方解码器版本，校验 IPA 包含 iPhone ARM64 的 VLC 显示组件。
- `OriginalPlaybackTests.swift`：实际 HTTP Range H.264 测试验证拖动中只更新预览、松手后跳转；本地播放会话测试验证小窗期间暂停、继续、跳转和恢复只使用一张原文件票。云端 Debug/Release 各 49 通过、3 跳过；iPhone Release 编译及 IPA 校验通过。

真机待验收：用 IPZZ-991 对比构建 20 的起播与跳转速度，点「小窗」后回桌面，测试暂停、跳转、返回全屏及声音；在普通播放器竖屏和横屏拖动画面，对照缩略图与落点，再确认播放墙只通过原进度条调整进度。用 MIDA-574 回归 AVPlayer 小窗。构建 20 保留回退。

---

# Peach iOS Test — 构建 20 验收

安装包：[Peach-iOS-Test-unsigned.20.ipa](C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.20.ipa)，17,160,095 字节，无签名 iPhone ARM64，iOS 17.0+。SHA256 `6236941b7e0fcf34161f9383d5a915416e9b98a9ffc9b239523d9037518ff8c9`。源码 `bffd25cf5061b0c1a8538d769a85935c6f85a71e`；Codemagic `6aef4b7524d1a22fe16b68e0`。本机校验及云端日志在 `artifacts/codemagic-20/`。

- `PlaybackController.swift`：普通全屏、沉浸和播放墙只请求 Peach 签发的原文件地址。MP4 等可用 AVPlayer 的格式保留系统播放器；不能解码或播放已开始却没有首帧时，切换本机 VLC，沿用同一地址及原进度、暂停和静音状态。MKV 直接走本机 VLC。原文件不可取时报告错误，正式播放不会请求服务端 HLS 计划。
- `VLCOriginalPlayer.swift`、`PlayerPresentation.swift` 及播放器视图：接入 MobileVLCKit 3.7.3、手势和进度；墙内和全屏迁移同一画面。系统画中画保留给 AVPlayer。大图短片预览、详情和进度条阅览图走原有路径。
- Debug/Release 各 48 通过、3 跳过。真实 HTTP Range 上 H.264 起播和拖动通过；控制器在无 AV 视频轨、格式错误和 MKV 时只向本机解码器传入原地址，未请求 HLS。验证暂停位置、静音、倍速、失活、旧请求不会复活及预览不记观看。iPhone 编译成功，IPA 内 VLC 已链接、仅 ARM64、未签名，并通过本机校验。

真机：覆盖安装后先打开 IPZZ-991，看是否出画面，单击画面确认标题下是「原文件直放 · VLC」，拖到没播过的位置。再从播放墙试播、切全屏及返回，检查画面和时间连续。用 MIDA-574 回归 AVPlayer 直放和系统小窗；用一部 MKV 验证本机播放。保留构建 19 回退。

---

# Peach iOS Test — 构建 19 验收

安装包：[Peach-iOS-Test-unsigned.19.ipa](C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.19.ipa)，1,552,673 字节，无签名 iPhone ARM64，iOS 17.0+。SHA256 `965a588b61f294e9c07ccd1c4fb6d20bcd982662fd041c4573c230f9422f6828`。源码 `618aac185ace1dabb2227bc672cceec8e3e09c60`；Codemagic `6aef3f1df43f28dd128f0a63`；日志及校验在 `artifacts/codemagic-19/`。

- `LibraryRootView.swift`：底栏恢复原来贴屏幕底边的 60 点布局。馆藏滚动区域接到栏顶，去掉额外的底部占位。
- `PeachAPI.swift`：原文件播放地址仍需有效登录。取票不附带浏览器来源头，避免域名反代的上游地址不同而返回 403。兼容回退和播放墙界面保留。
- 实际 Peach 0.52.0 对 HMN-834 验证：来源不匹配返回相同的 403 提示；认证后无来源头可取票，未认证仍为 401；签发地址的文件首尾均返回 206。仅取票与读文件，未更改服务端或馆藏。
- Mac Debug/Release 各 46 通过、3 跳过。反代条件下 H.264 直放及拖动、兼容回退和跨域拒绝通过；iPhone Release 编译与 IPA 校验通过。

真机覆盖安装后，滚动馆藏确认列表接到底栏，切换索引和我的，确认三个入口可用。用原域名试播 HMN-834 并拖动一次，再确认墙内播放。保留构建 18 回退。

---

# Peach iOS Test — 构建 18 验收

安装包：[Peach-iOS-Test-unsigned.18.ipa](C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.18.ipa)，1,552,120 字节，无签名 iPhone ARM64，iOS 17.0+。SHA256 `0f88a4be9ada0b5da11053f7efc974a1fbc12e04fff2185445fd1c0d69bbcf2b`。源码 `a50d94e310f07a7ff1fb902343aac4c6cad418e1`；Codemagic `6aef0d4804bc42b5d4ae7294`，日志和校验在 `artifacts/codemagic-18/`。保留构建 13 回退。

普通全屏、沉浸和播放墙内嵌优先通过 Peach 自带的限时链接按 Range 读取 MP4/M4V/MOV 原文件。系统无可解码的视频轨、报告格式错误或旧后端缺少该接口时，使用既有兼容流。墙内切全屏继续使用同一会话；布局、手势、大图停留预览、NAS iOS、软路由和源文件不变。

- `PeachAPI.swift`：使用现有登录获取原文件播放地址，只接受当前服务对应作品的地址。
- `PlaybackController.swift`、`PlayerPresentation.swift`、`ImmersiveView.swift`：选择直放或兼容流，兼容切换保留进度、暂停和播放计数；普通和墙内共用展示会话。
- 生产只读验证：IPZZ-991 与 MIDA-574 的文件头、中部和末尾均返回 `206`，字节与源文件一致。证据 `artifacts/original-playback-range-20261107.json`。
- Mac Debug/Release 各 46 通过、3 跳过；H.264 原文件起播、跳转、原尺寸帧解码，缺视频轨、解码报错回退、保留暂停位置和拒绝跨域地址均通过。HEVC `hev1` 原视频轨通过 HTTP 读取；云端 Mac 将它报告为不可解码，iPhone 实际画面和速度仍待验收。Release 编译与两端 IPA 校验通过，未启动模拟器。

真机先播放 IPZZ-991 和 MIDA-574，分别确认出画面、声音和跳到未播过位置的速度。单击显示控制栏，看普通播放器标题下方是否为「原文件直放」；出现「HLS 自适应分片」说明使用了兼容流。再从播放墙内播放同一部，切全屏并返回，确认进度和声音连续；顺手验收沉浸、MKV、双击和小窗。

---

# Peach iOS Test — 构建 13 验收

安装包：[Peach-iOS-Test-unsigned.13.ipa](C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.13.ipa)，1,537,197 字节，无签名 iPhone ARM64，iOS 17.0+。SHA256 `0ce060f8713ba2b4b8e59ebc3ce200825859625a1ca44496a91f7d86d8822efb`。源码 `e0fa70f10dafd085af952ddd6035f9e99009a93a`；Codemagic `6aeeebcf630282fcf14921fb`；日志及本机校验在 `artifacts/codemagic-13/`。构建 12 保留回退。

| 范围 | 修改与回归 |
| --- | --- |
| 详情预览 | PreviewFilmstrip.swift、ItemDetailView.swift、OriginalVideoFrame.swift：卡片从 144×81 到 288×162 点，点开先显示已有图。预览条可见时提前取一张原尺寸帧，复用正在加载的请求及原图缓存；切图、离开或进入播放时停止不再需要的取帧。允许 0.35 秒时间偏差以减少定位开销。 |
| 大图视频 | PreviewFilmstrip.swift、PlaybackController.swift、PreviewVideoSample.swift：等可显示的帧才替换封面；播放过约 1.4 秒才跳下一段。原采样点、停留 3 秒、静音和不计观看记录保持。普通、沉浸和播放墙使用原播放路径。 |
| 横屏进度 | PlayerView.swift、MediaArtwork.swift：普通播放横屏下时间、进度、按钮同一行，进度条保留拖动预览和 44 点触区。竖屏、沉浸、播放墙原布局保留。 |
| 导航黑边 | LibraryRootView.swift：列表与底栏共用安全区，去掉独立底部占位和分隔线。馆藏、索引、我的三个入口保持。 |

Codemagic Debug/Release 各 44 项：41 通过、3 跳过，iPhone Release 编译及两端 IPA 校验通过。OriginalVideoFrameTests.swift 实测 1280×720 原帧与 Range 缓存复用；让真实 AVPlayer 停住 1.55 秒，片段没有提前结束，恢复后正常完成。Linux 核心含本地 HTTP 续期用例 36 通过、2 隔离用例跳过。生产仅只读核对 START-108：4K、30 张现有预览，拼图约 203 KB。未改播放墙内嵌、NAS iOS、域名或服务端，未启动模拟器。

真机优先确认：详情点开及横滑预览是否立刻出图、原画切换速度；START-108 与另一部曾黑屏作品的大图静音预览；横屏拖动和小窗；馆藏列表贴到底栏，切换索引和我的正常。首次未缓存的 4K 原画仍取决于播放源与网络。

---

# 构建 12 — 独立登录与缓存验收记录

安装包：[Peach-iOS-Test-unsigned.12.ipa](C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.12.ipa)，1,511,320 字节，无签名 iPhone ARM64，iOS 17.0+。SHA256 `1cae105c790a73b240e2bfb96e5fd52da85e33f5e35a255ee5e839a27b89db97`。源码 `9e968bc9c11c7f94644695d329f716a075584ea2`；Codemagic `6aeed913ab4a65afcf3fa24c`；日志与本地校验在 `artifacts/codemagic-12/`。

- 普通播放直接全屏；普通和沉浸播放器取消影院模式，全屏图标切换横屏，保留小窗、长按 2×、双击分区、进度条和记录。播放墙的内嵌播放器未修改。
- 详情 30 张预览保留原时间点，点开时从播放流解码该时刻的原尺寸画面，支持双指缩放，缓存为无损 PNG。缩略条与进度条复用已有小图；没有重生成服务端预览。大图卡片仍在停留 3 秒后，依次播放总时长 8%、22%、36%、50%、64%、78%、90% 的静音短片段，约 1.4 秒跳一次。
- App 支持 HTTPS 域名及原局域网 HTTP 地址。成功登录后，密码按服务地址存 iOS 钥匙串；Cookie 失效可自动续登，退出登录清除保存的密码。构建 11 已登录的用户升级后，可以继续使用原 Cookie，首次重新输入密码时才会存入钥匙串。域名与反代由用户配置；本轮未改服务端、NAS iOS、构建 82 或媒体。
- 封面、预览拼图及已打开的原图跨重启缓存。大图 MP4 短片仅缓存用过且可验证的 Range 字节块；不支持此条件的 MP4 和 HLS 仍在线播放。每服务地址限制为图片/元数据 128 MiB、原图 256 MiB、视频片段 256 MiB，空间不足淘汰旧缓存。“我的 → 本机缓存”可以清除。

云端 Debug/Release 各 43 项：40 通过、3 跳过（2 个隔离实例测试、1 个本地 HTTP 测试），无失败。Mac 用实际 AVFoundation 对测试 MP4 解码 1280×720 并存 PNG，重开复用磁盘 Range 块；隔离实例的真实媒体流请求返回 503，实际馆藏的片段缓存待真机核验。本地 HTTP 测试通过：初次登录及 Cookie 清除后的并发请求，总共两次表单登录。IPA 本地独立校验与云端一致。未启动模拟器。

真机验收：

1. 覆盖安装构建 12，配置好的 HTTPS 域名首次输入密码后登录，结束 App 再打开无需输入；退出登录再打开需要重新输入。原局域网 IP 也可登录。
2. 详情点播放直接全屏；单击显示控制，点全屏图标进横屏，再返回；检查 MP4/MKV、进度条、长按、双击和 PiP。播放墙内嵌操作与构建 11 一致。
3. 详情点开 MP4 和 MKV 的预览图，检查实际像素、放大和横滑；再打开同一张图验证缓存。大图停留、滚动恢复封面和“我的”清除缓存正常。

源码改动按入口核对：

| 范围 | 修改文件 |
| --- | --- |
| 全屏与横屏 | PeachTestApp.swift、PlayerView.swift、PlaybackOrientation.swift、ImmersiveView.swift |
| 域名、密码与续登 | RootView.swift、PeachSession.swift、PeachAPI.swift、LoginPolicy.swift、LoginView.swift、SavedPeachPassword.swift、AccountHubView.swift |
| 原图与缓存 | OriginalVideoFrame.swift、PreviewFilmstrip.swift、MediaPresentation.swift、MediaArtwork.swift、RemoteImage.swift、MediaDiskCache.swift、CachedPreviewAsset.swift、PlaybackController.swift |
| 回归测试 | LibraryFilterTests.swift、LoginRecoveryTests.swift、MediaCacheTests.swift、OriginalVideoFrameTests.swift |

---

# 构建 11 — 视频预览与播放墙验收记录

更新：2026-11-07。构建 **11** 已完成编译、打包、下载及本地 IPA 校验，尚未作 iPhone 真机验收。构建 9 保留回退，NAS 82 不变。

- 安装包：[Peach-iOS-Test-unsigned.11.ipa](C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.11.ipa)，1,420,727 字节。
- SHA256：`389b6624b9870fbf9183054fe3c2910db88dc1e132577e80d3eabe5cc896674e`。
- 源码 `317464a7f5b52a482d86d250348d719277b6ec8e`；Codemagic `6aee9b179c7ac8eab4e9bc93`。
- 证据 `artifacts/codemagic-11/`：完整日志、云端和本地 IPA 校验；无签名 arm64、iOS 17.0。

Bundle ID `com.axcz1.peachios.test`，显示名 `Peach Test`，最低 iOS 17.0，独立测试版。

## 本轮修改

- 大图停留 3 秒后，封面位置播放静音原视频短片段，原版七个采样位置每 1.4 秒循环；保持竖卡尺寸，视频按原比例留黑边。滚动、切页、开详情、退后台停止并恢复封面，不写观看次数、活动及续播。用户录屏 12–20 秒是此行为，不是截图轮播。
- 每片 30 张截图：详情“记一次高潮”下方单行横向滚动，点图查看大图；进度条共用时间轴缓存。截图与卡片视频预览分开。
- 筛选仅一条横向滚动行，“换一批”固定最右；保留搜索、排序、小图和库切换。
- 普通/沉浸/播放墙长按 2×，松开、取消、拖进度、离开恢复；普通/沉浸原双击分区和单击显隐保留。
- 播放器增加影院、记录、画中画、全屏图标。影院扩展播放器并收起图库，全屏隐藏详情；共用当前播放器，PiP 保留会话并支持恢复。
- 播放墙采用 Peach 0.52.0 原 4 套 12 格模板及聚焦重排，二维平移、惯性、锚点缩放；筛选时有限集合，无筛选时探索续页后循环，保留图片/声音/详情/稍后看。

## 已验证与边界

- 本地核心 33 项：31 通过、2 项环境接口测试跳过；这 2 项随后单独在真实隔离实例通过。新增模板重排、负坐标、有限集合、探索续页、缩放锚点、停留选片、30 帧裁切检查。
- Codemagic Debug/Release 各 37 项：35 项通过，2 项局域网用例跳过（本地已通过），0 失败；实际 PlaybackController 的倍速恢复、PiP 会话及迟到计划测试通过。iPhone ARM64 Release 编译成功。
- 构建 10 因测试播放计划缺少必填 id 失败；修正数据并增加播放器创建断言后构建 11 通过。未用跳过测试绕过失败。
- IPA 本地重新校验 ZIP、Info.plist、arm64 Mach-O、无签名和 SHA256，结果与云端一致。
- NAS 82 仍为 19,135,903 字节，SHA256 FA01E9F509B5C269EDFF888FB872AE44624F050EB0BB16D799E8453D9C9E12E4；Actions disabled。
- 55 部缓存各 30 帧，元数据/JPEG 尺寸核实；示例 /api/timeline、/timeline 返回 200。
- 原 54 部源文件大小和 mtime 与生成前一致，后来新增第 55 条已由定时任务自动补齐。
- 生产镜像仍 longmeidao/peach:0.52.0，容器运行中。业务写接口只在隔离 peach-ios-test 回归并恢复测试计数。
- 未运行 Simulator。真机画面、手势、PiP、MP4/MKV 和流畅度待用户实测。

## 截图维护

scripts/generate-previews.py 部署到 /mnt/ssd/apps/peach/data/tools/peach-ios/，每 10 分钟检查已入库本地视频。用户仍须通过 Peach 原有扫描入库；已有匹配缓存跳过，不覆盖其他生成器缓存。

取 30 点：duration × (0.01 + i / 30)，i 为 0…29。2 小时影片约每 4 分钟一张，不是固定每 10 秒。使用官方抽帧函数、320 像素宽、10×3 拼图和原时间轴目录；镜像、数据库、源视频及挂载不改。失败显式记录。

状态 /data/generated/timeline/.fixed30-status.json；运行日志 /data/tools/peach-ios/last-run.log。原 crontab 备份 /mnt/ssd/apps/peach/backups/fixed30-20261107/root.cron。回退只移除 peach-ios-fixed30 标记行，不恢复整份旧 crontab 覆盖其他后来任务。缓存可保留。

## iPhone 验收

1. 更新 Peach Test，同 Wi-Fi 登录，与 NAS 82 共存。大图停留 3 秒播放原视频、无声音；滚动离开恢复正封，观看统计不变。
2. 详情计数下方可横向看完 30 张图，展开/翻页/关闭正常；拖进度条预览随时间变化，暂停拖动后仍暂停。
3. 筛选只有一行，左右滚动时换一批固定；回归搜索、标签、大小图、切库。
4. MP4/MKV 普通/沉浸长按 2×，释放恢复；取消、切后台、拖动不残留倍速。回归双击分区、单击显隐、上下翻页。
5. 影院/全屏不重新起播；记录及撤销只处理本次；进入小窗、后台继续、点小窗恢复、关闭均正常，无第二路声音。
6. 播放墙平移、捏合、缩放、聚焦重排及收起恢复相机；图片、声音、播放、详情、稍后看、全屏返回回归。
7. 索引头像、资料、精确时长、评分、喜欢、观看进度和登录回归。

## 修改文件对应

- LibraryRootView、PeachCard、PreviewFilmstrip、MediaPresentation：停留视频、详情截图及单行筛选。
- PlaybackController、MediaGestureOverlay、PlayerView、PlayerPresentation、ImmersiveView、PeachTestApp、Info.plist：倍速、模式、PiP 生命周期。
- VideoWallView、WallFocusView、WallLayout、WallTemplates：原版几何、探索与聚焦。
- generate-previews.py、import-wall-templates.py：官方兼容缓存和模板导入。
- WallPreviewTests、PlaybackLifecycleTests：核心算法及实际播放器回归。
