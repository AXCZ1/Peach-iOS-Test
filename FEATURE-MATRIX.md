# Peach iOS 功能对照表

基准：软路由容器 longmeidao/peach:0.52.0（http://192.168.5.5:8900/），网页与容器内 peach 包源码；交互参考 NAS iOS。
更新：2026-11-06。

状态含义：

- 已实现：iOS 有真实入口并调用同一接口。
- 已实现·待真机：代码与接口已完成，iPhone 上的交互/解码尚待验收。
- 只读：iOS 能查看，但原版写操作会改生产馆藏或需要桌面/服务端环境，本轮不提供入口。
- 受限：iPhone 能力或 0.52.0 接口不支持，已写明原因。

## 播放器与浏览

| 原版入口 | 实际行为 | 接口 | iOS 入口 | 状态 |
| --- | --- | --- | --- | --- |
| 顶栏「沉浸模式 · 随机连播」 | 按当前筛选取最多 60 条可直接播放的作品，打乱后全屏上下翻页；横滑拖动进度，双击左/右半屏 ±10 秒，单击暂停；动作列「不喜欢／看过／记一次高潮」，高潮显示实时计数；播完自动下一条，接近队尾续取 | GET /api/items?sort=rand|seed&limit=60&offset=0、GET /api/item、GET /api/stream-plan、POST /api/play、POST /api/activity、POST /api/feedback | 馆藏右上角沉浸按钮；ImmersiveView | 已实现·待真机 |
| 详情「记一次高潮」 | o_count += 1；回执更新计数，可撤销（o-undo，下限 0）；重开详情读回 | POST /api/feedback {"kind":"o"}、{"kind":"o-undo"}、GET /api/item | 详情主按钮；沉浸动作列 | 已实现；隔离实例已验证递增、撤销、读回 |
| 详情评分 | 0–100 分存储，五颗星每次 ±20；点当前星取消，写回 NULL 而不是 0 | POST /api/feedback {"kind":"rate","value":n} | 详情五星 | 已实现；隔离实例已验证 80 分与清除 |
| 详情「稍后看」 | 加入/移出 watch_queue，回执布尔；卡片与播放墙显示书签 | POST /api/watch-later | 详情动作行、播放墙工具 | 已实现；隔离实例已验证写入、读回、移除 |
| 详情「喜欢」 | 写 asset_preference，参与「已标记」与推荐 | POST /api/preference | 详情动作行 | 已实现；隔离实例已验证 |
| 详情「不合口味／看过了」 | 同值再点取消，不同值互斥 | POST /api/feedback | 详情动作行 | 已实现·待真机 |
| 播放记忆 | 本地记播放秒数，重开续播；播完清零；服务端 leave_ratio 兜底 | 本地 UserDefaults + GET /api/item.leave_ratio | 播放器与沉浸页 | 已实现·待真机 |
| 观看统计 | 首次起播 play_count += 1；每 10 秒、暂停、拖动、结束上报真实观看秒数、位置、seek 次数 | POST /api/play、POST /api/activity | PlaybackController | 已实现；隔离实例已验证 activity 回执 |
| 播放源 | 服务端给 HLS 就播 HLS，否则 Range MP4；每格独立流会话，关闭时取消 | GET /api/stream-plan、POST /api/stream-cancel | PlaybackController | 已实现·待真机（MP4/MKV） |
| 顶栏「播放墙」 | 二维封面墙，封面/缩略图切换；点开一张放大，墙后留暗场；可播放、稍后看、看详情、缩放；进入时有声（与网页一致） | GET /api/items、GET /api/cover、GET /api/thumb、POST /api/watch-later | 馆藏右上角播放墙；VideoWallView | 已实现·待真机 |
| 顶栏「密度：大图 / 密集」 | 网页 localStorage.density 在 336px 与 168px 间切换，只影响目录网格，重开保留 | 本地存储 | 馆藏右上角密度按钮；Preferences.density | 已实现；手机为 1 列/2 列 |
| 图片页大图/小图 | 网页照片页用 photoSize，与视频网格密度分开保存 | 本地存储 | 本实例未做照片墙 | 受限：当前馆藏无照片墙页面；未造空壳 |
| 首页状态 | 全部／没看过／稍后看／已标记；fresh 为未播且无反馈，flagged 为高潮>0 或喜欢 | GET /api/items?state= | 馆藏状态条 | 已实现；隔离实例已验证 fresh/flagged/later 计数 |
| 首页排序 | 随机（种子，无方向）、评分、高潮计数、观看次数、时长、体积、入库时间、观看时间、发行时间；点当前列翻方向 | GET /api/items?sort=&dir=&seed= | 排序菜单 + 换一批 | 已实现；隔离实例已验证 seed/rating/o/dur |
| 搜索 | 片名、番号、演员、标签；三字以上走 FTS，短词走 LIKE；搜索历史服务端保存 | GET /api/items?q=、GET/POST /api/search-history | 搜索框 + 历史建议 | 已实现；隔离实例已验证 JUQ=2 |
| 筛选 | 演员、标签、厂牌、系列、创作者、状态 | GET /api/items、GET /api/facets、GET /api/index | 筛选面板、索引页、详情标签/演员 | 已实现；隔离实例已验证演员 5、标签 14、厂牌 7 |
| 索引页 | 演员／厂牌／标签／系列／创作者名册，带头像与作品数 | GET /api/index?kind=、GET /api/entity-image | 底部「索引」 | 已实现 |
| 资料页 | 实体图、别名、作品数、标签、共演/名册、作品网格、实体收藏 | GET /api/entity、GET /api/items、GET/POST /api/library-shortcuts | 详情演员/标签、索引页 | 已实现；实体收藏隔离实例已验证 |
| 详情页 | 封面、番号、标题、时长/画质/大小、发行日、演员、标签、文件、进度、写操作 | GET /api/item | 馆藏卡片 | 已实现 |
| 播放列表 | 网页可建、改名、删、排序、移出；列表卡显示续播位置 | GET /api/playlists、GET/POST /api/playlist | 我的 → 播放列表；可建、打开续播 | 部分实现：新建与打开播放；改名/排序/删除未做 |

## 馆藏与个人记录

| 原版入口 | 实际行为 | 接口 | iOS 入口 | 状态 |
| --- | --- | --- | --- | --- |
| 首页卡片 | 封面、番号、标题、演员、时长、进度、稍后看/标记角标 | GET /api/items、GET /api/cover | 馆藏网格 | 已实现 |
| 观看历史 | 统计页最近观看（名称、进度、时间） | GET /api/stats | 我的 → 统计与观看历史 | 已实现；可点开作品 |
| 任务中心 | 进行中/已结束任务、阶段、进度、状态 | GET /api/tasks | 我的 → 任务中心 | 只读 |
| 配置 | 版本、端口、目录、访问模式、媒体工具、隧道、更新 | GET /api/configuration | 我的 → 数据管理 | 只读；修改属服务端操作 |
| 扫描与资料处理 | 全库扫描、补全资料、重试、暂停 | POST /api/library-processing 等 | 我的 → 数据管理显示状态 | 只读；启动全库任务不拿生产库测试 |
| 关注 | 来源、作者、分组、新作、已保存、忽略、播放进度 | GET /api/follow 等 | 我的 → 数据管理显示计数与来源数 | 只读；添加/删除来源需要网页 |
| 下载 | 115/PikPak 任务、取消、后处理 | GET /api/downloads、POST /api/downloads* | 我的 → 数据管理显示可用性与任务数 | 只读；本实例未配置下载渠道 |
| 人工复核 | 字段候选、批准/拒绝、按资产 | GET /api/review、POST /api/review/decision | 未提供 | 受限：改动会写生产账本，本轮未做；有接口可后续补 |
| 回收站 | 列表、还原、永久清除 | GET /api/items?state=trash、POST /api/batch | 未提供 | 受限：删除类操作不在本轮测试版范围 |
| 数据清理/重复/垃圾 | 重复扫描、垃圾队列、批量处置 | /api/duplicates、/api/ads、POST /api/batch | 未提供 | 受限：同上 |

## 设置与外观

| 原版入口 | 实际行为 | 接口 | iOS 入口 | 状态 |
| --- | --- | --- | --- | --- |
| 界面密度 | 目录大图/小图，写入 localStorage | 本地 | 馆藏密度按钮 | 已实现并保留 |
| 播放墙图片 | 封面/缩略图，属于本次播放墙会话 | 本地 | 播放墙工具菜单 | 已实现并保留 |
| 播放墙声音 | 网页无独立持久静音项；iOS 提供声音开关，默认有声 | 本地 | 播放墙顶栏 | 已实现 |
| 前进/后退秒数 | 网页播放器设置 seekSeconds 默认 10 秒；iOS 默认同为 10 秒，暂无设置入口 | 本地 | 暂无设置入口 | 差异已记录 |
| 主题、强调色、光斑 | 网页外观设置 | 本地 | 固定深色（NAS 参考） | 未做 |
| 关注初始天数、搜索历史上限、演员名语言等 | /api/settings | 同左 | 未提供 | 只读未做 |
| 访问密码、隧道、自动更新、API 令牌 | 配置页写操作 | POST /api/configuration/* | 未提供 | 受限：认证/公网变更不在本轮范围 |

## 明确未做的部分

- 沉浸模式在 iPhone 上只实现一个活动播放器，预加载下一张封面；原版桌面会在 DOM 里保留相邻两格播放器。手机端同时解码多路 4K 不划算，以真机流畅度为先。
- 播放墙是手机尺寸的 12 格拼贴 + 聚焦层，没有桌面播放墙的无限世界平移和相机缩放；封面/缩略图、聚焦播放、稍后看、详情与声音均已覆盖。
- 管理页只读。0.52.0 的扫描、复核、清理、下载和认证写接口都存在，但这些操作会改生产馆藏或服务端状态，未拿真实库验证，也未做空壳按钮。
- 播放列表只做新建和续播；改名、删除、拖拽排序留在下一阶段。
- 未运行 iOS Simulator、UI 自动化或 GitHub Actions。所有真机结论待用户验收。

## 验证证据

- 隔离实例：容器 peach-ios-test，同一 0.52.0 镜像，复制 /data 到 /tmp/peach-test-data，监听 192.168.5.5:18900，未改生产容器与配置。
- 写入读回：o 1→2、o-undo 2→0、rate 80→null、watch-later true→false、preference liked=true、activity delta=10/position=120、实体收藏 on→off。
- 生产只读复核：JUQ-575 的 o_count/rating/watch_later/liked/play_count/leave_ratio 均保持空/0，收藏清单为空。
- 本地核心包：swift test 10 项通过（登录期限、地址校验、筛选默认值、facets/index 解码、写接口回执、排序方向、密度枚举）。


