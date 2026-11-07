# Peach iOS Test — 视频预览与播放墙验收

更新：2026-11-07。本轮实现及本地检查已完成，准备手动 Codemagic 构建，尚未作 iPhone 真机验收。构建 9 保留回退，NAS 82 不变。

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
- SwiftUI 修改文件语法解析通过；完整 iOS 编译及 Mac 播放器用例由 Codemagic 执行。语法检查不能代替编译。
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
