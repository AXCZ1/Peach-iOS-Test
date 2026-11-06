# Peach iOS Test — 真机验收

构建 **5**：`C:\Users\mo\Downloads\Peach-iOS-Test-unsigned.5.ipa`

SHA256：`bfa148b0d7d75147e82bddcc8a3fa55afbbb2e9946797badbe433aeeb995341b`

Bundle ID：`com.axcz1.peachios.test`。显示名称 `Peach Test`，与 NAS 构建 82
（`com.axcz1.nasios`）不同，可同时安装。

## 已完成的自动验证

- 独立仓库与独立 Codemagic 应用；只触发 `ios-unsigned-ipa`，没有 Simulator 或 GitHub Actions。
- Debug 与 Release 各 4 项核心测试通过。
- 无签名 iPhone ARM64 Release 编译通过。
- IPA 结构、Bundle ID、显示名、最低 iOS、arm64、无签名与无描述文件均已校验。
- 真实 Peach 实例只读接口：馆藏 54 部、搜索、演员/标签/厂牌筛选、详情、封面。
- MP4：`/api/stream-plan` 返回 `range`，`/stream` 实测 `206 video/mp4` 且带 Range。
- MKV：`/api/stream-plan` 返回 `hls`，播放列表和首个 `video/mp2t` 分片实测成功。
- 表单登录 `/login`（`token`、`next`、`days`）实测能取得 `peach_session`，随后 API 返回 200。

## 需要你在 iPhone 上验收

1. 用 Sideloadly 或你现有的无签名安装方式安装构建 5，并确认它能与 NAS 构建 82 同时存在。
2. 打开 `Peach Test`，确认地址默认为 `http://192.168.5.5:8900/`，输入 Peach 访问密码。
3. 浏览馆藏，打开搜索，试一个番号（如 `JUQ`）和演员/标签筛选，确认封面、标题、番号显示。
4. 打开一个 MP4 作品（例如 `JUQ-575`），确认能播放；再验证拖动进度、暂停/继续和 ±15 秒。
5. 打开一个 MKV 作品（例如 `SONE-081`），确认 HLS 播放与拖动进度；如失败，记录具体错误提示。

本轮没有执行真机安装、播放或手势验收；上述结果仍需你实际测试。

构建 4 是上一版校验包，保留在 Downloads；构建 5 是当前交付。构建 4 与 5
的 IPA 文件名不同，已同时存在，均未覆盖 NAS 构建 82。
