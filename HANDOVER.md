# Peach iOS Test 当前交接

更新日期：2026-11-06。最新交付是独立测试 App 构建 **8**，未接入 NAS iOS；NAS 构建 82 未改动、未覆盖、未重新打包。用户已确认登录问题解决，本轮未改动登录语义。

## 当前项目路径和运行方式

- 【PC PowerShell｜项目目录 C:\Users\mo\Documents\Codex\Peach-iOS-Test】独立 SwiftUI 工程，独立仓库 https://github.com/AXCZ1/Peach-iOS-Test，分支 main。
- 原 NAS iOS 工程 C:\Users\mo\Documents\Codex\NAS-ios 只作设计参考；未修改其源码、分支、构建配置或产物。
- 后端默认地址 http://192.168.5.5:8900/，测试 App 内可修改。实际部署为 Peach 0.52.0，访问密码模式；媒体库“夯”，当前接口返回 54 部作品。
- 工程为 PeachTest.xcodeproj，scheme PeachTest；Bundle ID com.axcz1.peachios.test，显示名 Peach Test，最低 iOS 17.0，仅 iPhone ARM64。
- IPA 入口是 codemagic.yaml 中唯一的 ios-unsigned-ipa，只手动触发。Codemagic 应用 ID 6aed85f0165a22c4d4b043a0。构建脚本 scripts/build-unsigned-ipa.sh；不跑 Simulator，不启用 GitHub Actions。
- 构建 8 源码提交：b993ab02fcde3fd79055e171c649178d5b6b9e1f；构建 ID：6aedb851ec37262835fae34c。
- 交付文件：C:\Users\mo\Downloads\Peach-iOS-Test-unsigned.8.ipa，1,165,459 字节，SHA256 E99A1F09EB445B4AAC76225F478DC65E7A8037F489809649431255BB3399E7AD。
- 构建 7 的 NAS-unsigned .7.ipa 保留在 Downloads 作为上一版校验包（SHA256 D80FC449E6D8E4931CC3E13373CFD5DDCE251CDB26E432E5DD788EC65F730BEB）。
- 验证证据：artifacts/codemagic-8/，包括 IPA、构建日志；构建日志里 Debug/Release 各 13 项测试通过，BUILD SUCCEEDED。

## 当前功能状态

- 已实现：登录、馆藏网格、封面/标题/番号、搜索与历史、状态条、排序与换一批、演员/标签/厂牌筛选、索引页、资料页与实体收藏、详情页。
- 播放：AVPlayer + HLS 播放计划、每会话取消、续播记忆、起播计数与每 10 秒观看统计、±10 秒、拖动。
- 浏览体验：沉浸模式（随机 60 条、上下连播、单击暂停、双击左右跳 10 秒、横滑 seek、动作列与高潮计数）、播放墙（12 格拼贴、封面/缩略图、声音、聚焦层、稍后看/详情）、大图/小图密度并保留选择。
- 个人记录：记一次高潮与撤销、评分与取消、稍后看、喜欢、看过、不合口味，均以服务端回执刷新；详情、卡片与播放墙显示状态。
- 管理只读：任务中心、配置、扫描/资料处理、关注、下载状态；不提供删除、复核、下载提交、认证或部署写操作。
- 功能对照表：FEATURE-MATRIX.md，逐项列出原版入口、实际行为、接口、iOS 入口与验收状态。
- 真机安装、播放、手势和沉浸/播放墙的实际体验尚未验证；不能以编译和接口探测代替真机结论。

## 本轮验证证据

- 隔离实例：容器 peach-ios-test，同一 0.52.0 镜像，复制 /data 到 /tmp/peach-test-data，监听 192.168.5.5:18900；未改生产容器、配置或媒体。
- 写接口读回：o 1→2、o-undo 2→0、rate 80→null、watch-later true→false、preference liked=true、activity delta=10/position=120、实体收藏 on→off。
- 生产只读复核：JUQ-575 的 o_count/rating/watch_later/liked/play_count/leave_ratio 仍为空/0，收藏清单为空。
- 本地 WSL Swift 6.1.3：swift test 13 项通过；Codemagic 构建 8 的 Debug/Release 13 项测试均通过，无签名 iPhone ARM64 Release 编译与 IPA 校验通过。

## 当前稳定备份

- 独立仓库 GitHub 远程 main 指向 b993ab0，是构建 8 的可追溯回退点。
- 构建 8 是待真机验收的交付候选，不是已验收稳定版；构建 7 为上一版校验包。
- NAS 构建 82 保持原状：C:\Users\mo\Downloads\NAS-unsigned .82.ipa，19,135,903 字节，SHA256 fa01e9f509b5c269edff888fb872ae44624f050eb0bb16d799e8453d9c9e12e4。

## 必须遵守的规则

- 沿用本任务的 iOS 规则：仅手动触发 Codemagic ios-unsigned-ipa；不跑 Simulator；不启用 GitHub Actions；验收以 iPhone 真机为准。
- 不修改或覆盖 NAS 工程及构建 82。测试版交付后停在这里，必须等用户明确同意才能接入 NAS iOS。
- 管理写操作、删除、迁移、认证、挂载和全库任务不以生产库为测试环境；真实馆藏只做只读探测。
- 具体 Git、备份和交接规则见 C:/Users/mo/.codex/instructions/git-safety.md、C:/Users/mo/.codex/instructions/recovery-handover.md；iOS 执行规则参考 C:/Users/mo/Documents/Codex/NAS-ios/AGENTS.md。

## 未解决问题

- 构建 8 尚未完成 iPhone 真机安装、与构建 82 共存、同 Wi-Fi 登录、浏览/搜索、详情、MP4/MKV 播放、拖动和手势验收。
- HLS 仅验证到服务端播放列表与首个分片；AVPlayer 在真实 iPhone 上的 HLS 兼容性、起播延迟、拖动与 MKV 解码仍需实测。
- 沉浸模式只保留一个活动播放器；播放墙是手机尺寸拼贴，没有桌面播放墙的无限世界平移。
- 播放列表只做新建与续播；改名/删除/排序未做。
- 照片墙大图/小图未做（当前实例无照片墙页面）。

## 下一步任务

1. 用户安装构建 8，按 ACCEPTANCE.md 验收第 1 组（沉浸、播放墙、大小图、记一次高潮），反馈实际结果。
2. 保持 NAS 构建 82 和原 NAS 工程不变；不要自行重新构建或接入。
3. 只有用户明确同意接入 NAS iOS 后，才在独立测试版基础上评估集成范围。


