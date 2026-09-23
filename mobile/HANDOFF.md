# wintouchspace 移动 App — 交接说明

外贸 CRM/MES 系统 wintouchspace 的 iOS 客户端。已在真机跑通：登录、取数、离线缓存。

> 状态：**功能完整，代码侧已达可提审状态**。5 个 tab + 12 个子模块全部接真实数据，18 条路由全量冒烟通过。
> 唯一没做的是推送——它卡在「还没买 Apple 开发者账号」，不是卡在代码。

---

## 1. 技术栈

| | |
|---|---|
| 壳 | Capacitor 8.5 |
| 前端 | Vue 3.5 + Vite 6 + Tailwind 3.4 + Pinia |
| 原生插件 | geolocation, push-notifications, network, preferences, haptics, keyboard, status-bar, app |
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

**脏数据客户传附件会 500 且文件直接丢**（2026-09-11 已修）
存量 / 小满迁入的客户常有不合法字段（典型：`trade_country` 存成 ISO 码 `IT`，而模型白名单要的是 `ITALY`）。
这类记录跑不过校验 → `files.attach` 内部的 save **静默失败** → 附件停在未保存状态 → 序列化时 `url_for` 拿不到
signed_id → 整个请求 500，文件也没了。修法是 `customers_controller#attach` 里存不下就 `save(validate: false)` 再存一次
（传附件跟客户字段合不合法无关）。**网页端同样受影响，这个修复对两端都生效。**
同类风险：任何「先 attach 再渲染」的接口，遇到校验不过的父记录都会这样。

## 6. 上架准备

**代码侧已完成**（都在版本控制里，不用再改）：

- App 图标换成品牌标志：1024×1024、**不透明、不自带圆角**（iOS 自己切，自带会双重圆角）。
  由 `public/favicon-512x512.png` 抠出标志本体、重摆在品牌紫 `#785CF5` 纯底上生成，启动图同色系。
- `PrivacyInfo.xcprivacy` 已建并加进 target 的 Resources：声明不做追踪、五类收集数据（邮箱/姓名/精确位置/照片/其它用户内容，
  全部 Linked + AppFunctionality、非追踪），以及 UserDefaults 的 required-reason（CA92.1）。
  Capacitor 各 framework 自带各自的清单，不用在这里重复声明。
- `Info.plist` 收敛：去掉 `NSAllowsArbitraryLoads`；`UIRequiredDeviceCapabilities` 由 `armv7` 改 `arm64`；
  锁死竖屏；权限文案对齐实际用途（相机/相册＝拍附件，定位＝考勤打卡校验）。
- `TARGETED_DEVICE_FAMILY` 由 `1,2` 改 **1（仅 iPhone）**——UI 是竖屏手机版，声明支持 iPad 会要求 iPad 截图与可用布局。
- 登录页不再暴露 `HTTP xxx · ERR_xxx` 之类底层错误，改为「邮箱或密码不正确」「连不上服务器，请检查网络后重试」。
- 移除了没在用的 `@capacitor/camera`（附件走原生 `<input type="file">`，iOS 的系统面板本身就含拍照）。

`NSAllowsLocalNetworking` 与 `NSLocalNetworkUsageDescription` 保留：连局域网 dev 后端要用，且不会触发审核问题。

**必须由账号持有人做的四件事**（代码帮不了）：

1. **加入 Apple Developer Program**（$99/年）。公司名义上架要先申请 **D-U-N-S 邓白氏编码**（免费，1–2 周）；
   个人名义可即时开通，但商店会显示个人名。这是所有后续步骤的前置。
2. **移动应用备案**（工信部）。2023-09 起中国大陆上架强制，**网站备案不能替代**，App 要单独备案，走云服务商提交。周期长，建议与第 1 项并行启动。
3. App Store Connect 建 App 记录、注册正式 Bundle ID、填元数据与截图。
4. 隐私政策公开 URL。

当前签名状态：只有免费个人团队 `Amber Law (X5H8DLC948)` 与 `Apple Development` 证书，
**没有 `Apple Distribution` 证书**（要付费账号才建得出），描述文件是 Xcode 托管的开发 profile、7 天一过期。

## 7. 功能清单

底部 5 个 tab：工作台 / 客户 / 邮件 / 审批 / 更多。其余模块收在「更多」页与工作台九宫格里
（清单见 `src/constants/modules.js`，两处共用同一份，且只渲染路由里真实存在的项，永远不会点出死链）。

| 模块 | 内容 |
|---|---|
| 登录 | 含会话上限的设备选择与踢出 |
| 工作台 | 待办四格（可点击直达）+ 九宫格快捷入口 + 本年 KPI + 本月目标进度 + 今日日程 |
| 客户 | 列表/搜索/我的·全部·公海；详情含商机·订单·PI·生产·跟进·文件·操作历史七段；新建/编辑 + 建档查重；记跟进；附件增删；认领 / 转公海 / 分配 |
| 邮件 | 收件箱·未读·星标·已发送·草稿 + 搜索 + 手动收信；详情含 HTML 正文净化、附件、星标、打开即已读、标记未读、删除；写信/回复，支持模板套用、附件、**AI 写信 / 翻译 / 往来摘要** |
| 审批 | 待我审批·我发起的·抄送我·我已审批；详情含表单与审批流；同意 / 驳回 / 撤回；**发起审批**（模板 → 7 种字段动态表单 → 提交，可带附件）；**申请人改单** |
| 考勤 | 上下班打卡、外勤打卡、本月记录与异常统计。考勤组开了地理围栏才取定位，否则不向用户要位置权限 |
| 日程 | 按天分组的月视图、上下月切换、新建/编辑/删除、勾完成、关联客户 |
| 销售单据 | 商机 / 销售订单 / 报价单 / PI 四类的列表（状态筛选 + 搜索）与详情（含明细行与附件） |
| 产品与核价 | 产品库搜索；核价表按产品线切换，宽表在手机上按行拆成卡片，支持表内搜索 |
| 知识库 | 公司资料 / 我的文档、搜索、详情（正文净化 + 附件下载） |
| 数据 | 我的目标（结转口径与网页端同一份实现，见 `src/composables/useTargetRows.js`）、团队看板 |

**只剩推送没做**：`@capacitor/push-notifications` 已装但未接后端。推送 entitlement 需要**付费 Apple Developer Program**，
当前是免费个人证书，拿不到。账号到位后再接，代码侧没有别的障碍。

扫码 tab 已移除（原先扫到的码没接任何业务逻辑）。若要做 MES 报工/出入库，新加一个入口即可，别再放进底部 tab。

**附件上传已在 iOS 运行时验证通过**（2026-09-11，iPhone 17 Pro 模拟器）。Capacitor 8 的 XHR 拦截会把 FormData 里的 `File` 读成 base64、
交原生重组 multipart（见 `Capacitor.framework/native-bridge.js` 的 `convertFormData`）。注意它**只认真正的 `File` 对象**——`Blob` 会被当成
字符串丢掉，所以 `AttachmentField` 用的是原生 `<input type="file">`（iOS 点它的系统面板本身就含拍照/相册/浏览三项，不必再接 Camera 插件）。

> 这一步是有价值的：浏览器里附件上传是通的，**到了原生壳里却 500**。根因不在桥而在后端——见下面「已知的坑」里的脏数据条目。
> 教训：只在浏览器 viewport 里测移动端，测不出原生层的问题，关键路径要进模拟器跑。

## 8. 自动化验证脚本

都在 `~/acrm-migration/sop-crm/_shooter/`，需先 `pnpm dev` 起 :5273 且 dev 后端 :3001 在跑：

| 脚本 | 覆盖 |
|---|---|
| `test_mobile_home.mjs [邮箱]` | 工作台取数、待办点击跳转（传不同账号可验权限口径） |
| `test_customer_detail.mjs` | 客户列表 → 详情 → 分段 → 跟进弹层 → 新建表单 → 查重 |
| `test_customer_write.mjs` | 建档 → 跳详情 → 编辑回填与生效 → 记跟进落库 |
| `test_mobile_mail.mjs` | 邮件列表/分段/搜索 → 详情（正文/横向溢出）→ 回复预填 |
| `test_mobile_mail_send.mjs` | 真实走 SMTP 发信（dev 发件箱指向 mailhog:1025，可在 :8026 查收） |
| `test_mobile_approvals.mjs` | 待我审批 → 详情 → 同意，校验状态与意见回显 |
| `test_mobile_approval_new.mjs` | 发起审批：选模板 → 七种字段动态表单 → 必填校验 → 提交 |
| `test_mobile_approval_edit.mjs` | 申请人改单：入口可见性、回填、改后生效 |
| `test_mobile_attachments.mjs` | 写邮件带附件发送 + 审批提单带附件（校验 ActiveStorage 落库与 MIME 附件）|
| `test_mobile_attendance.mjs` | 更多 tab → 打卡页 → 上班/下班打卡 → 记录回显 |
| `test_mobile_schedule.mjs` | 日程 CRUD + 勾完成 + 关联客户 |
| `test_mobile_records.mjs` | 商机/订单/报价/PI 四类列表与详情，并断言**不泄露成本与毛利** |
| `test_mobile_products.mjs` | 产品库 + 核价表（含宽表卡片化） |
| `test_mobile_docs.mjs` | 知识库列表与详情 |
| `test_mobile_targets.mjs` | 我的目标（结转口径、NaN 回归）与团队看板 |
| `test_mobile_customer_ops.mjs` | 客户附件增删、操作历史、归属弹层 |
| `test_mobile_mail_extras.mjs` | 草稿分段、模板套用、AI 写信/翻译、更多操作弹层 |
| `test_mobile_smoke_all.mjs [邮箱]` | **全量冒烟**：18 条路由逐个打开，查加载失败/页面异常/横向溢出 |
| `test_nan_sweep.mjs [邮箱]` | 全路由扫 `NaN / undefined / [object Object]` 这类渲染事故 |

### 进模拟器跑（能测出浏览器测不出的原生层问题）

```bash
VITE_API_BASE=http://localhost:3001 pnpm build && npx cap sync ios
cd ios/App && xcodebuild -project App.xcodeproj -scheme App \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath /tmp/wtsim build
xcrun simctl boot "iPhone 17 Pro"; xcrun simctl install booted /tmp/wtsim/Build/Products/Debug-iphonesimulator/App.app
xcrun simctl launch booted com.wintouchspace.app
xcrun simctl io booted screenshot /tmp/shot.png          # 截图（启动后等 10s 再截，否则抢在绘制前）
xcrun simctl spawn booted log show --last 2m --predicate 'process == "App"' --style compact   # 看日志
```

模拟器点不了屏幕。要跑交互用例，就临时加一个自跑自报的页面、把 `/` 重定向过去，验完删掉——
本轮的原生 multipart 问题就是这么抓出来的。**测完记得把 `VITE_API_BASE` 去掉重新构建**，否则产物里烘的是 dev 地址。
| `test_offline.mjs` | 断网后离线横幅、缓存落款、不白屏（App Review 会查这个） |

跑写入类脚本会在 dev 库留数据（客户/审批/邮件名字都带 `ZZ` 或「移动端…测试」前缀），测完记得删。

两个 dev 环境的坑：
- **反复跑测试会把测试账号的会话撑到上限**（默认 25），之后登录页会弹设备选择而不是直接进。清一下即可：
  `docker exec wintouch-crm-postgres-1 psql -U postgres -d chatwoot_dev -c "UPDATE users SET tokens='{}' WHERE email='sales@acme.inc';"`
- dev 库**没有任何部门主管**，含「部门主管」环节的模板提单会 422 报「审批流未找到有效审批人」。要测这条路径得临时给部门设 leader 并给申请人加 `org_memberships`，测完还原。
- `sales@acme.inc` 在 dev 库里的 `crm_role` 其实是 **deputy_admin**，不是普通业务员。要验「业务员看不到什么」得另找账号或临时改角色。
- dev 库里**没有邮件模板**，模板弹层会显示空态。
- 后端凡是走 SQL `SUM()` 的金额字段（`actual_amount_micros` 等）在 JSON 里是**字符串**（BigDecimal，如 `"407499542000.0"`）。
  直接 `+=` 会变成字符串拼接、几步之后算出 NaN。统一用 `src/utils/format.js` 的 `num()` 过一道。

## 9. 参考

后端 API 位于主工程 `app/controllers/api/v1/accounts/crm/`，网页版页面在 `app/javascript/dashboard/routes/dashboard/crm/pages/`（65 个页面，可作为移动端功能对照）。
