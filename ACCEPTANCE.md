# Peach iOS Test — 构建 12 验收

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
