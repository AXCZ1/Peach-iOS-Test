# Peach iOS Test — 修复版验收

更新：2026-11-07。构建 **9** 已完成编译、打包、下载及本地校验；构建 8 保留作回退。构建 9 的真机验收尚未进行。

- 安装包：[Peach-iOS-Test-unsigned.9.ipa](C:/Users/mo/Downloads/Peach-iOS-Test-unsigned.9.ipa)，1,284,041 字节。
- SHA256：`e7d6c34268f802d3f5b53ab037ba0d744fd33ef068731d5b417fd2599f0dd687`。
- 源码提交：`80075b14988034803363dff9f03cde8047f6e2d4`；Codemagic 构建 ID：`6aee0c4c52103eb5dbe40626`。
- 证据目录：`artifacts/codemagic-9/`，含完整编译步骤日志、云端 IPA 校验及本地下载校验。

Bundle ID `com.axcz1.peachios.test`，显示名 `Peach Test`，最低 iOS 17.0。与 NAS 构建 82 分开安装，尚未接入 NAS iOS。

## 本轮修改

- 修复详情重复撤销、非活动页迟到起播、沉浸无撤销、手动翻页不续载、准备完成误记观看次数。
- 修复索引图片及资料的 kind 参数；真实无数据与读取失败分别显示。
- 馆藏大图使用 3:4 正封裁切，补全演员头像、日期、大小和标签；显示精确到秒的时长。
- 普通与沉浸播放采用相同双击分区：左 25% 后退 10 秒，中央 50% 播放/暂停，右 25% 前进 10 秒。单击显隐，去掉中央三个控制按钮。
- 拖动时读取已有时间轴或九宫格显示缩略图；不重新生成、不修改源视频。暂停状态下拖动后仍保持暂停。

## 已有证据

- 本地 WSL Swift 6.1.3：27 项测试通过，包括真实隔离 Peach 的索引/图片/封面字段读取，以及计数 5→6→5；连续消费同一撤销操作只发送一次。测试后隔离影片计数恢复原值。
- Codemagic Mac 主机 Debug/Release 各 29 项：27 项通过、2 项真实局域网接口测试因云端未提供凭据而跳过，0 失败；这 2 项已在本地真实隔离实例通过。
- 新增 Mac 主机测试调用实际 PlaybackController，检查打开详情及退出后迟到计划不能创建播放器，两项均通过。
- 无签名 iPhone ARM64 Release 编译通过；云端校验 IPA 结构、Bundle ID、版本、iOS 17.0、arm64 及无签名；本地重新验证 ZIP、Info.plist、Mach-O 和 SHA256 后复制到 Downloads。
- 两部示例片的 /thumb 为已有 1440×810 九宫格，/api/timeline 为空；按浏览器九段映射选图。密集时间轴分片/外部 cues/缺省数据路径有核心测试。
- NAS 构建 82 基线 SHA256：FA01E9F509B5C269EDFF888FB872AE44624F050EB0BB16D799E8453D9C9E12E4，19,135,903 字节。

## iPhone 验收

1. 直接更新安装新的 Peach Test，确认登录和 NAS 82 共存。
2. 索引检查头像、厂牌 Logo、分类切换，点入演员/标签/厂牌确认仅显示关联作品。创作者为空时显示空状态。
3. 大图对照用户图 3：竖向正封、头像与信息行；MIKR-051 显示 2:29:08。切回小图，搜索与筛选仍可用。
4. 普通播放和沉浸分别测试横竖屏 25%/75% 分界、快速连续双击、中央双击暂停与继续、单击显隐。进度条和按钮不能误触视频手势。
5. 拖进度条，确认预览跟随目标时间、靠边不越界、松手跳转；原本暂停时不能自动播放。两部示例是已有九宫格，预览按分段变化。
6. 沉浸上下翻页、打开详情、立即退出和重新进入，确认没有上一页声音或迟到起播；保留横滑定位。
7. 详情和沉浸各记录一次并连续点撤销，确认只撤回该次；记录后翻页再撤销，确认作用于原影片。此步会产生并撤回用户自己的真实记录。
8. 回归 MP4/MKV 播放、声音、续播、播放墙聚焦、大小图选择、评分/稍后看/喜欢及返回路径。

超过 60 条的分页状态使用 125 条测试场景检查；当前生产库 54 条，不能据此声称真机超 60 条翻页已通过。最终播放、手势与视觉结论只以真机验收为准。

## 修改范围与构建

- 核心：PeachAPI/PeachModels/MediaPresentation/PlaybackController，接口映射、预览元数据和播放状态。
- 界面：EntityBrowseView、ItemDetailView、ImmersiveView、PlayerView、PeachCard/LibraryRootView、MediaArtwork/MediaGestureOverlay/RemoteImage。
- Package.swift 将实际播放器纳入可用 AVFoundation 的 Mac 主机测试；Linux 条件编译跳过该部分。
- 仅手动触发 Codemagic ios-unsigned-ipa；不启用 GitHub Actions，不运行 Simulator。未修改生产服务或源媒体。
- 完整功能目标中的其余待实现项继续保留在 FEATURE-MATRIX.md，本轮不扩展管理写操作。
