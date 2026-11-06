# Peach iOS Test 当前交接

更新日期：2026-11-06。最新交付是独立测试 App 构建 **5**，未接入 NAS iOS；NAS 构建 82 未改动、未覆盖、未重新打包。用户已确认登录问题解决，并明确要求不再处理该问题。

## 当前项目路径和运行方式

- 【PC PowerShell｜项目目录 `C:\Users\mo\Documents\Codex\Peach-iOS-Test`】独立 SwiftUI 工程，独立仓库 `https://github.com/AXCZ1/Peach-iOS-Test`，分支 `main`。
- 原 NAS iOS 工程 `C:\Users\mo\Documents\Codex\NAS-ios` 只作设计参考；不得修改其源码、分支、构建配置或产物。
- 后端默认地址 `http://192.168.5.5:8900/`，测试 App 内可修改。实际部署为 Peach 0.52.0，访问密码模式；媒体库为“夯”，当前接口返回 54 部作品。
- 工程为 `PeachTest.xcodeproj`，scheme `PeachTest`；Bundle ID `com.axcz1.peachios.test`，显示名 `Peach Test`，最低 iOS 17.0，仅 iPhone ARM64。
- IPA 入口是 `codemagic.yaml` 中唯一的 `ios-unsigned-ipa`，只手动触发。Codemagic 应用 ID `6aed85f0165a22c4d4b043a0`。构建脚本为 `scripts/build-unsigned-ipa.sh`，在 macOS 上执行；不跑 Simulator，不启用 GitHub Actions。
- 构建 5 源码提交：`87a0a3b044555fb63b92a6545f7cd03a7ad87a88`；构建 ID：`6aed8829c8686d389dfac2c2`。当前 `main` 后续只有交付文档提交。
- 当前工作区存在未提交的登录相关改动（`LoginPolicy.swift` 及 `PeachSession`、`PeachAPI`、`RootView`、`LoginView`、测试文件的修改）。用户已确认登录问题解决并要求不再处理；保留现状，不把构建 5 称为包含这些改动的版本。

## 当前功能状态

- 已实现原生登录、馆藏网格、封面/标题/番号、搜索、演员/标签/厂牌筛选、详情、AVPlayer 播放和 HLS 播放计划。
- 业务请求只读：没有播放历史、评分、收藏、管理、刮削、下载或文件操作写入。
- 构建 5 已通过 Debug/Release 各 4 项核心测试、无签名 iPhone ARM64 Release 编译及 IPA 校验。
- 真实后端只读验证通过：54 部馆藏、`JUQ` 搜索、演员/标签/厂牌筛选、详情、封面；MP4 `/stream` 实测 `206 video/mp4` 并支持 Range；MKV 播放计划返回 HLS，首个 `video/mp2t` 分片返回 200。
- 表单登录 `/login` 实测可取得 `peach_session` 并访问 API。
- 交付文件：`C:\Users\mo\Downloads\Peach-iOS-Test-unsigned.5.ipa`，522,877 字节，SHA256 `bfa148b0d7d75147e82bddcc8a3fa55afbbb2e9946797badbe433aeeb995341b`。
- 构建 4 的 `Peach-iOS-Test-unsigned.4.ipa` 作为上一版校验包保留在 Downloads。
- 验证证据：`artifacts/codemagic-5/`，包括 IPA 校验 JSON、SHA256、构建日志和构建摘要。
- 真机安装、与构建 82 共存、登录、播放、拖动进度及 MKV 实际兼容性尚未验证；不能以编译和接口探测代替真机结论。

## 当前稳定备份

- 本轮没有新增源码备份；独立仓库的 GitHub 远程 `main` 和构建 5 源码提交是可追溯回退点。
- 构建 5 是待真机验收的交付候选，不是已验收稳定版；构建 4 是上一版校验包。
- NAS 构建 82 保持原状：`C:\Users\mo\Downloads\NAS-unsigned .82.ipa`，19,135,903 字节，SHA256 `fa01e9f509b5c269edff888fb872ae44624f050eb0bb16d799e8453d9c9e12e4`。

## 必须遵守的规则

- 沿用本任务的 iOS 规则：仅手动触发 Codemagic `ios-unsigned-ipa`；不跑 Simulator；不启用 GitHub Actions；验收以 iPhone 真机为准。
- 测试版只读，不写播放历史、评分、收藏，不改后端配置或媒体文件；不把凭据写入源码、日志或构建产物。
- 不修改或覆盖 NAS 工程及构建 82。测试版交付后停在这里，必须等用户明确同意才能接入 NAS iOS。
- 具体 Git、备份和交接规则见 `C:/Users/mo/.codex/instructions/git-safety.md`、`C:/Users/mo/.codex/instructions/recovery-handover.md`；iOS 执行规则参考 `C:/Users/mo/Documents/Codex/NAS-ios/AGENTS.md`。

## 未解决问题

- 构建 5 尚未完成 iPhone 真机安装、与构建 82 共存、同 Wi-Fi 登录、浏览/搜索、详情、MP4/MKV 播放和拖动进度验收。
- HLS 仅验证到服务端播放列表和首个分片，AVPlayer 在真实 iPhone 上的 HLS 兼容性、起播延迟、拖动和 MKV 解码仍需实测。
- 当前工作区登录修复未提交、未重新构建；用户已确认登录问题解决，不把它作为待办，也不要回退这些改动。
- App 通过 `NSAllowsArbitraryLoads` 访问局域网 HTTP；若后续改为 HTTPS，应重新核对 ATS 和登录流程。

## 下一步任务

1. 用户安装构建 5，按 `ACCEPTANCE.md` 完成真机验收并反馈实际结果。
2. 保持 NAS 构建 82 和原 NAS 工程不变；不要自行重新构建或接入。
3. 只有用户明确同意接入 NAS iOS 后，才在独立测试版基础上评估集成范围，并继续保护构建 82 的独立 Bundle ID 与产物。
