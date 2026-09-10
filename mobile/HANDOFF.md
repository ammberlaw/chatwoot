# wintouchspace 移动 App — 交接说明

外贸 CRM/MES 系统 wintouchspace 的 iOS 客户端。已在真机跑通：登录、取数、原生相机扫码、离线缓存。

> 状态：**可运行的骨架**。5 个 tab 中 3 个已接真实数据，邮件/审批为占位。完成度约 35%。

---

## 1. 技术栈

| | |
|---|---|
| 壳 | Capacitor 8.5 |
| 前端 | Vue 3.5 + Vite 6 + Tailwind 3.4 + Pinia |
| 原生插件 | camera, barcode-scanner, push-notifications, network, preferences, haptics, keyboard, status-bar, app |
| 后端 | Rails（Chatwoot fork），仓库根目录的主工程 |

**Capacitor 8 使用 SPM 而非 CocoaPods**，因此没有 `App.xcworkspace`。用 xcodebuild 时必须 `-project App.xcodeproj`，用 `-workspace` 会报 "does not exist"。

## 2. 跑起来

```bash
pnpm install

# 浏览器调试（/api 与 /auth 经 vite 代理到 vite.config.js 里的 DEV_BACKEND）
pnpm dev                 # http://localhost:5273

# 装到真机
VITE_API_BASE=http://<后端可达地址>:3001 pnpm build
npx cap sync ios
cd ios/App
xcodebuild -project App.xcodeproj -scheme App \
  -destination "id=<设备UDID>" -configuration Debug \
  -allowProvisioningUpdates -derivedDataPath /tmp/build build
xcrun devicectl device install app --device <设备UDID> \
  /tmp/build/Build/Products/Debug-iphoneos/App.app
```

设备 UDID：`xcrun xctrace list devices`

## 3. 接手后必须改的三处

| 位置 | 当前值 | 说明 |
|---|---|---|
| `ios/App/App.xcodeproj/project.pbxproj` → `DEVELOPMENT_TEAM` | `X5H8DLC948` | 换成你们自己的 Apple Team ID，或在 Xcode 的 Signing & Capabilities 里重选 |
| `capacitor.config.json` → `appId` | `com.wintouchspace.app` | Bundle ID。改动前请确认与 App 备案信息一致 |
| `vite.config.js` → `DEV_BACKEND` | `http://localhost:3001` | 浏览器调试时的后端地址 |

生产 API 地址硬编码在 `src/api/client.js` 的 `API_BASE`（`https://wintouchspace.com`）。

## 4. 关键决策（改之前先看这里）

**认证用 devise_token_auth，不要用 `api_access_token`**
后端两种认证都支持，但 `api_access_token` 是**下划线**请求头，生产 nginx 默认会丢弃下划线 header，App 会静默认证失败。因此走 `/auth/sign_in`，用 `access-token` / `client` / `uid` 三个连字符头。见 `src/api/client.js`。

**启用了 CapacitorHttp**
让 XHR 走原生层，规避 webview 跨域。副作用：请求行为与浏览器不完全一致（FormData 上传等需实测）。

**色板复用主仓，不要另建一套**
`tailwind.config.js` 直接 import 主仓的 `../theme/colors` 和 `../theme/icons`；`src/style.scss` import 主仓的 `_next-colors.scss`（CSS 变量定义）。主仓改色，App 自动跟随。**若把本目录单独抽离出主仓，这些相对路径会断，需要把这两份文件复制进来。**

**离线判定用三重信号**
`src/stores/network.js`：插件状态 + App 回前台复查 + **请求失败本身**。只依赖 `networkStatusChange` 事件不可靠（App 前台运行时切飞行模式该事件不一定触发）。
注意不要在 `reportRequestFailure` 里调 `refresh()` —— 插件状态会把刚设的离线值覆盖回在线（`navigator.onLine` 常年为 true）。

**本地缓存**
`src/api/client.js` 的 `cachedGet()`：成功写 Preferences，失败回落缓存。这是为了让 App 断网时仍显示有意义的内容 —— App Review 会在飞行模式下检查，白屏会按 Guideline 4.2 判定为"套壳网页"而拒。

## 5. 已知的坑

**登录设备数达上限会返回 409**
后端以 `user_agent.include?('Mozilla')` 判定是否浏览器请求，而 WKWebView 的 UA 恰好含 `Mozilla`，所以 App 被当作浏览器：达到 `MAX_USER_SESSIONS`（默认 25）时返回 **409 + 会话列表**，而不是自动踢出最旧会话。
`src/pages/LoginPage.vue` 已实现设备选择与踢出（`revoke_session_id` / `revoke_all_sessions`）。**删掉这段逻辑会导致用户换机或重装累计到上限后彻底无法登录且无从自解。**

**真机调试前置**
- iPhone 需开启开发者模式（设置 → 隐私与安全性 → 开发者模式），**必须重启并在解锁时确认**才生效
- 免费个人 Apple ID 签的 App **7 天后过期**，重装即可

**`limitsNavigationsToAppBoundDomains` 不要开**
该项要求 Info.plist 配 `WKAppBoundDomains` 白名单，白名单为空等于掐断所有网络请求，表现为"请检查网络"。

**后端未执行的迁移会导致所有请求 500**
排查登录问题时先看后端日志，不要先怀疑 App。

## 6. 上架前必须移除的调试项

- `ios/App/App/Info.plist` → `NSAppTransportSecurity.NSAllowsArbitraryLoads`（放宽了明文传输，仅为连局域网 dev 后端）
- `src/pages/LoginPage.vue` → 登录失败时显示的底层错误详情（`HTTP xxx · ERR_xxx`），应还原为用户友好文案

`NSAllowsLocalNetworking` 和相机/相册的 `NSUsageDescription` 是正当项，保留。

## 7. 当前进度与待办

| 页面 | 状态 |
|---|---|
| 登录 | ✅ 含会话上限处理 |
| 工作台 | ✅ 4 张 KPI + 离线缓存（网页版有 17 个 widget） |
| 客户 | ✅ 列表 + 搜索 + 离线缓存；无详情页、不能增改 |
| 扫码 | ✅ 原生相机可用，**但扫到的码尚未接任何业务逻辑** |
| 邮件 | ⬜ 占位 |
| 审批 | ⬜ 占位 |

建议优先级：扫码接 MES 报工/出入库 → 审批（推送 + 一键批）→ 邮件 → 客户详情页。

其它待优化：`ScanPage` 的 chunk 有 339KB，因为打包了浏览器降级用的 `html5-qrcode`，iOS 上用不到，可按平台剥离。

## 8. 参考

后端 API 位于主工程 `app/controllers/api/v1/accounts/crm/`，网页版页面在 `app/javascript/dashboard/routes/dashboard/crm/pages/`（65 个页面，可作为移动端功能对照）。
