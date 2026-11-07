# 当前继续点（2026-11-07）

独立 App **构建 13** 已打包和校验，等待 iPhone 验收。仅改 App 的四项反馈：详情预览宽高各翻倍、秒开已有图并提前取原画；大图预览首帧与缓冲；横屏进度区；馆藏导航上方黑边。播放墙内嵌、NAS iOS、域名、后端和媒体未改。

- IPA：C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.13.ipa；1,537,197 字节；SHA256 `0ce060f8713ba2b4b8e59ebc3ce200825859625a1ca44496a91f7d86d8822efb`。
- 源码 `e0fa70f10dafd085af952ddd6035f9e99009a93a`，Codemagic `6aeeebcf630282fcf14921fb`。Debug/Release 各 41 通过、3 跳过。原帧和缓冲时钟测试通过，未启动模拟器。
- 真机验证按 ACCEPTANCE.md 首节，优先 START-108 大图、冷取 4K 原画、横屏与底栏。回退包保留构建 12，回退前源码状态为 `0aef8d3`。

## 构建 12 历史

当前交付是独立 App **构建 12**，用户自行配置域名，本轮只改 App；不接入 NAS iOS，也不改播放墙内嵌播放器、服务端或媒体。

- IPA：C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.12.ipa；1,511,320 字节；SHA256 `1cae105c790a73b240e2bfb96e5fd52da85e33f5e35a255ee5e839a27b89db97`。
- 构建 12 源码 `9e968bc9c11c7f94644695d329f716a075584ea2`；Codemagic `6aeed913ab4a65afcf3fa24c` 已完成，证据在 `artifacts/codemagic-12/`。Debug/Release 各 40 通过、3 跳过；本地 HTTP Cookie 续期测试通过，真机待验收。
- PlayerView、ImmersiveView、PlaybackOrientation：去掉影院模式，普通播放直接全屏，按钮切换横屏。WallFocusView、VideoWallView 未改；正常播放会话及 PiP 路径保留。
- PeachSession、SavedPeachPassword、PeachAPI：HTTPS 域名、设备钥匙串及 Cookie 续期；无服务端认证改动。MediaDiskCache、CachedPreviewAsset、OriginalVideoFrame、PreviewFilmstrip：封面、原尺寸预览、受限 MP4 片段缓存。HLS 预览视频仍在线播放。
- 验收见 ACCEPTANCE.md 首节。回退：构建 11 IPA 保留；修改前源码 bundle `backups/standalone-cache-20261107-152305/source.bundle`（`fc0205f`）。NAS 82 SHA256 已核对无变化。继续仅手动跑 Codemagic `ios-unsigned-ipa`，不启用 Actions、不启动 Simulator。

## 构建 11 历史

本轮已授权执行，不再是规划任务。视频预览、30 张截图、单行筛选、倍速、播放模式及原版播放墙已交付构建 11。未接入 NAS iOS，不动构建 82。下文构建 9 是回退历史。

- 用户录屏 QQ2026117-25419.mp4 的 12–20 秒是封面内静音原视频短片段，不是图片轮播；30 张图用于详情/进度条。
- 构建 11：源码 317464a7f5b52a482d86d250348d719277b6ec8e；Codemagic 6aee9b179c7ac8eab4e9bc93，finished。
- IPA：C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.11.ipa；1,420,727 字节；SHA256 389b6624b9870fbf9183054fe3c2910db88dc1e132577e80d3eabe5cc896674e。
- Debug/Release 各 35 通过、2 个 LAN 用例跳过（本地通过），Release 编译、云端及本地 IPA 校验完成；真机未验收。构建 10 测试 fixture 缺 id 的失败已修复，不能把 10 交付。
- 此处交付后只更新文档，不为文档触发构建；下一步由用户验收大图静音片段、手势、PiP 和播放墙。
- 本地 33 项核心及单独 2 项真实隔离接口回归无失败。Mac AVFoundation 4 项已在云端 Debug/Release 均通过。
- 生产官方 0.52.0 容器新增兼容缓存助手和每 10 分钟 cron，媒体只读；55 部各 30 帧。原 54 个源大小和 mtime 不变，第 55 条自动补齐。
- 助手路径、算法、cron 备份及回退见 ACCEPTANCE.md；不可恢复整份旧 cron 覆盖其他任务。
- 修改前源码备份 backups/previews-wall-20261107-024810/source.bundle，回退 f4fbcd8。
- 只执行 ios-unsigned-ipa，不启用 Actions，不启动 Simulator。

---

# Peach iOS Test 当前交接

更新日期：2026-11-07。最新交付是独立测试 App 构建 **9**，已编译、打包并校验，等待用户真机验收。未接入 NAS iOS；NAS 构建 82 未改动、未覆盖、未重新打包。用户已确认登录问题解决，本轮未改动登录语义。

## 当前项目路径和运行方式

- 【PC PowerShell｜项目目录 C:\Users\mo\Documents\Codex\Peach-iOS-Test】独立 SwiftUI 工程，独立仓库 https://github.com/AXCZ1/Peach-iOS-Test，分支 main。
- 原 NAS iOS 工程 C:\Users\mo\Documents\Codex\NAS-ios 只作设计参考；未修改其源码、分支、构建配置或产物。
- 后端默认地址 http://192.168.5.5:8900/，测试 App 内可修改。实际部署为 Peach 0.52.0，访问密码模式；媒体库“夯”，当前接口返回 54 部作品。
- 工程为 PeachTest.xcodeproj，scheme PeachTest；Bundle ID com.axcz1.peachios.test，显示名 Peach Test，最低 iOS 17.0，仅 iPhone ARM64。
- IPA 入口是 codemagic.yaml 中唯一的 ios-unsigned-ipa，只手动触发。Codemagic 应用 ID 6aed85f0165a22c4d4b043a0。构建脚本 scripts/build-unsigned-ipa.sh；不跑 Simulator，不启用 GitHub Actions。
- 构建 9 源码提交：80075b14988034803363dff9f03cde8047f6e2d4；构建 ID：6aee0c4c52103eb5dbe40626。
- 交付文件：C:\Users\mo\Downloads\Peach-iOS-Test-unsigned.9.ipa，1,284,041 字节，SHA256 e7d6c34268f802d3f5b53ab037ba0d744fd33ef068731d5b417fd2599f0dd687。
- 构建 8 回退包：C:\Users\mo\Downloads\Peach-iOS-Test-unsigned.8.ipa，1,165,459 字节，SHA256 E99A1F09EB445B4AAC76225F478DC65E7A8037F489809649431255BB3399E7AD；源码 b993ab02fcde3fd79055e171c649178d5b6b9e1f。
- 构建 7 的 NAS-unsigned .7.ipa 保留在 Downloads 作为上一版校验包（SHA256 D80FC449E6D8E4931CC3E13373CFD5DDCE251CDB26E432E5DD788EC65F730BEB）。
- 验证证据：artifacts/codemagic-9/，包含 IPA、完整编译步骤日志、云端与本地 IPA 校验；Debug/Release 各 27 项通过、2 项局域网测试跳过、0 失败，BUILD SUCCEEDED。

## 当前功能状态

- 已实现：登录、馆藏网格、封面/标题/番号、搜索与历史、状态条、排序与换一批、演员/标签/厂牌筛选、索引页、资料页与实体收藏、详情页。
- 播放：AVPlayer + HLS 播放计划、每会话取消、续播记忆、起播计数与每 10 秒观看统计、±10 秒、拖动。
- 浏览体验：沉浸模式（固定随机种子按 60 条续载、上下连播、左右各 25% 双击跳 10 秒、中央双击播放/暂停、单击显隐、横滑 seek、动作列与计数撤销）；普通播放器采用同一双击分区。播放墙保留 12 格拼贴、封面/缩略图、声音、聚焦层、稍后看/详情。
- 馆藏大图：3:4 正封及演员头像、日期、大小、标签；小图选择保持持久化。时长精确到秒。两种播放器拖动进度条读取已有时间轴/九宫格预览，缺少预览时不生成新文件。
- 个人记录：记一次高潮与撤销、评分与取消、稍后看、喜欢、看过、不合口味，均以服务端回执刷新；详情、卡片与播放墙显示状态。
- 管理只读：任务中心、配置、扫描/资料处理、关注、下载状态；不提供删除、复核、下载提交、认证或部署写操作。
- 功能对照表：FEATURE-MATRIX.md，逐项列出原版入口、实际行为、接口、iOS 入口与验收状态。
- 用户此前已安装构建 8 并提供截图；构建 9 的真机安装、播放、手势及视觉效果尚未验证，不能以编译和接口探测代替真机结论。

## 本轮验证证据

- 隔离实例：容器 peach-ios-test，同一 0.52.0 镜像，复制 /data 到 /tmp/peach-test-data，监听 192.168.5.5:18900；未改生产容器、配置或媒体。
- 本轮隔离接口测试：实际 PeachAPI 计数 5→6→5，重复消费同一撤销只发送一次；结束后恢复隔离影片原计数。读取真实索引、实体资料、头像、正封字段与已有预览图成功。
- 生产仅只读复核：JUQ-575 的 o_count/rating 为空、watch_later/liked 为 0；当前 play_count=2、leave_ratio=0.16163170874744334，是读取时的真实值，不能沿用构建 8 的全零记录。本轮未在生产写测试记录。
- 本地 WSL Swift 6.1.3：27 项通过，含 2 项隔离实例测试。Codemagic 构建 9 的 Debug/Release 各 27 项通过、2 项局域网测试跳过；新增实际 PlaybackController 迟到计划测试通过；无签名 iPhone ARM64 Release 编译与 IPA 校验通过。

## 当前稳定备份

- 构建 9 源码已推送至独立仓库 main 的 80075b1；之后仅更新交付文档，不为文档再触发构建。
- 构建 9 是待真机验收的交付候选；构建 8 保留作回退。修改前回退点 b347adc，源码 bundle：backups/player-fixes-20261106-195853/source.bundle。
- NAS 构建 82 保持原状：C:\Users\mo\Downloads\NAS-unsigned .82.ipa，19,135,903 字节，SHA256 fa01e9f509b5c269edff888fb872ae44624f050eb0bb16d799e8453d9c9e12e4。

## 必须遵守的规则

- 沿用本任务的 iOS 规则：仅手动触发 Codemagic ios-unsigned-ipa；不跑 Simulator；不启用 GitHub Actions；验收以 iPhone 真机为准。
- 不修改或覆盖 NAS 工程及构建 82。测试版交付后停在这里，必须等用户明确同意才能接入 NAS iOS。
- 管理写操作、删除、迁移、认证、挂载和全库任务不以生产库为测试环境；真实馆藏只做只读探测。
- 具体 Git、备份和交接规则见 C:/Users/mo/.codex/instructions/git-safety.md、C:/Users/mo/.codex/instructions/recovery-handover.md；iOS 执行规则参考 C:/Users/mo/Documents/Codex/NAS-ios/AGENTS.md。

## 未解决问题

- 构建 9 尚未完成 iPhone 真机安装、与构建 82 共存、同 Wi-Fi 登录、浏览/搜索、详情、MP4/MKV 播放、拖动和手势验收。
- HLS 仅验证到服务端播放列表与首个分片；AVPlayer 在真实 iPhone 上的 HLS 兼容性、起播延迟、拖动与 MKV 解码仍需实测。
- 沉浸模式只保留一个活动播放器；播放墙是手机尺寸拼贴，没有桌面播放墙的无限世界平移。
- 播放列表只做新建与续播；改名/删除/排序未做。
- 照片墙大图/小图未做（当前实例无照片墙页面）。

## 下一步任务

1. 用户安装构建 9，按 ACCEPTANCE.md 验收索引、大图、时长、普通/沉浸手势、进度预览和撤销，反馈实际结果。
2. 保持 NAS 构建 82 和原 NAS 工程不变；不要自行重新构建或接入。
3. 只有用户明确同意接入 NAS iOS 后，才在独立测试版基础上评估集成范围。



## 构建 9 修复交付（2026-11-07）

用户已授权本会话执行：此前 5 个缺陷、索引、大图正封样式、统一双击手势、已有进度缩略图、精确时长。代码、相关测试、Mac 编译、IPA 下载校验均已完成；构建 9 已放到 Downloads，等待真机反馈。

- 改动和真机验收清单见 ACCEPTANCE.md；完整功能目标的后续项见 FEATURE-MATRIX.md。
- 回退点 b347adc，修改前源码 bundle 位于 backups/player-fixes-*；没有备份或修改真实媒体。
- 预览只读 /api/timeline、/timeline、/thumb，九宫格在客户端裁切，不调用服务端生成接口。
- 两种播放模式统一左右各 25% ±10 秒、中央 50% 播放/暂停，单击显隐；用户已确认该交互。
- Codemagic API 凭据来自本机进程环境 CODEMAGIC_API_TOKEN，不写入文档或仓库。
- 本轮交付到此，仍不得自行接入 NAS iOS。继续任务时以用户真机反馈为准，不重复触发已成功的同提交构建。
