# A-CRM · 外贸出口销售 CRM

> 一套**外贸出口销售 CRM**,以**原生模块**的形式重写并内嵌在 Chatwoot 分支中(Ruby on Rails + Vue 3)。
> 前身是基于 Twenty 的声明式 A-CRM,本项目将其全部功能用 Rails Model/Migration/API/Vue/RSpec 原生重写,
> 拥有独立的暖冷玻璃质感外壳,不依赖 Chatwoot 的客服会话形态。

底座 README(Chatwoot 原文)见 [`README.md`](./README.md)。本文件是 A-CRM 的**完整框架说明**。

---

## 目录
- [技术栈](#技术栈)
- [整体架构](#整体架构)
- [数据模型](#数据模型)
- [功能模块](#功能模块)
- [权限模型（RBAC）](#权限模型rbac)
- [目录结构](#目录结构)
- [后端 API 命名空间](#后端-api-命名空间)
- [UI / 设计系统](#ui--设计系统)
- [本地开发与运行](#本地开发与运行)
- [代码约定](#代码约定)

---

## 技术栈

| 层 | 技术 |
|---|---|
| 后端 | Ruby on Rails 7.1、PostgreSQL(pgvector)、Sidekiq、ActiveStorage、`audited`、`Net::IMAP`、`Mail` |
| 前端 | Vue 3(`<script setup>` 组合式)、Vue Router、Pinia、Tailwind CSS、Chart.js / vue-chartjs |
| 实时/异步 | Sidekiq + sidekiq-cron(`config/schedule.yml`) |
| 运行 | Docker Compose(rails / sidekiq / postgres / redis / vite / mailhog) |

一切 A-CRM 代码收敛在独立命名空间(`crm` / `chat` / `org` / `oa`),**不改 Chatwoot 核心**;唯一例外是为定制外观改的应用外壳与侧边栏(`Dashboard.vue`、`components-next/sidebar/*`)。

---

## 整体架构

```
┌───────────────────────── 前端 (Vue 3) ─────────────────────────┐
│  工作台 Launcher  →  各业务系统页面(玻璃面板)                   │
│  routes/dashboard/crm/pages/*.vue      (19 个页面)             │
│  api/crm|chat|org|oa/*.js  ⇄  stores/crm/*  (Pinia)           │
└───────────────────────────────┬───────────────────────────────┘
                                 │ HTTP (accountScoped)
┌───────────────────────────────┴───────────────────────────────┐
│                        后端 (Rails)                            │
│  controllers/api/v1/accounts/{crm,org,oa}/*  (29 controllers) │
│    └─ Crm::BaseController: 入口门禁 + 按负责人数据范围         │
│  models/{crm,chat,org}/*   policies/crm/*   services/crm/*     │
│  jobs/crm/*  (SMTP 发信 / IMAP 收信 / 公海回收)               │
└───────────────────────────────────────────────────────────────┘
```

**分层原则**:每个声明在 Twenty 里是配置,在这里都是一套 `Model + Migration + Controller + Jbuilder + Policy + Vue + Store + API client`。Chatwoot 没有 Company 对象,故 `Crm::Customer` 是关联到 Chatwoot `Contact` 的新模型。

---

## 数据模型

### CRM 销售域(`app/models/crm/`)
| 模型 | 说明 / 关键字段 |
|---|---|
| `Customer` | 外贸客户(关联 Chatwoot Contact)。`account_owner_id` 负责人、`is_in_public_pool` 公海、自增编号 `WT%07d`、16 项完善度评分+等级、`customer_status`、`trade_country/customer_group/product_group/source_channel/customer_level`、`move_to_public_pool!` |
| `Opportunity` | 商机。`owner_id`、`crm_customer_id`、`sales_stage`(NEEDS_CONFIRMED/SAMPLING/WON/LOST)、`amount_micros`、`probability`、`expected_close_date`、`loss_reason` |
| `Product` | 产品目录(全员共享) |
| `Quote` / `QuoteLineItem` | 报价单(自增 `QT-` 号)+ 明细(下单产品快照);级联删除 |
| `SalesOrder` | 销售订单。`owner_id`、自增 `order_no`(SO-)、必传 PI 附件、成交额 rollup 回写客户、`crm_quote_id` |
| `Email` / `EmailOpen` | CRM 邮件。SMTP 发 + IMAP 收;`folder`(INBOX/SENT/DRAFT/BULK/**SPAM 垃圾邮件**)、`send_status`、`tracking_token`(打开追踪)、`message_id`(IMAP 去重)、`chatwoot_message_id`(渠道镜像去重) |
| `MailAccount` | 业务员邮箱。SMTP(host/port/user/加密密码)+ IMAP(host/port/ssl/enabled/synced_at);服务商主机内置(腾讯/网易/阿里企业邮) |
| `EmailTemplate` | 邮件模板 |
| `KnowledgeDoc` / `KnowledgeCategory` | 资料库文档 + 分类。`scope`(PERSONAL/COMPANY 可见范围)× `library`(SALES 销售资料 / GENERAL 全公司文档)两维;ActiveStorage 附件 |
| `FollowUpNote` / `FollowUpTask` | 跟进记录 / 任务(自动回写客户 `last_follow_up_at`) |
| `SalesTarget` | 业绩目标(按月归一,每人每月一条,支持结转) |
| `Team` | CRM 团队(`account_users.crm_team_id`) |
| `PublicPoolSetting` | 公海回收开关(账号级单例) |

### 协同 / 组织(`app/models/{chat,org}/`)
| 模型 | 说明 |
|---|---|
| `Chat::Conversation` / `Message` / `Participant` | 内部团队 IM(单聊 `direct` / 群聊 `group`,已读回执) |
| `Org::Department` | 部门树(`leader_id` 负责人,支持子部门 `subtree_ids`) |
| `Org::Membership` | 部门成员归属(`title` 职位、`is_primary` 主负部门) |

### 扩展到 Chatwoot 核心表
- `account_users`:新增 `crm_role`(manager/sales)、`crm_team_id`。
- Chatwoot `Contact` 上挂 person 自定义字段;`Company` 用不到(隐藏)。

---

## 功能模块

工作台(`crm/workspace`)是登录落地页,以「选系统」卡片进入各模块:

1. **CRM 客户管理** — 客户建档(实时查重、自动编号、完善度评分)→ 私海/公海(超期自动回收进公海)→ 商机 → 报价 → 销售订单(成交额 rollup)。
2. **邮件中心** — 三栏邮件客户端。**发件**:每人配 SMTP 邮箱,多部件 HTML+文本、附件、知识库附件快照、打开追踪像素;`Crm::SendEmailJob → EmailSendService`。**收件**:`Crm::FetchImapEmailsJob`(每 5 分钟)→ `ImapFetchService` 拉 INBOX、按 Message-ID 去重、关联客户、存附件、连接/整体超时。**镜像**:`CrmEmailListener → EmailIntakeService` 把 Chatwoot 邮件渠道消息镜像进来。
   - **多邮箱侧边栏** — 每个文件夹下列「全部 + 本人在『邮箱账户』里配置的各邮箱」,可切换、带当前文件夹口径的计数;邮箱**按人隔离**(各账号只看/管自己配置的,含主账号),`emails#mailboxes` + `mail_accounts` 均 `owned_by(current_user)`。
   - **「我的/团队」切换** — 管理员/主管按角色范围(`scope_by_owner`)在「我的邮件 / 团队邮件」间切换,团队模式可下钻到指定成员。
   - **垃圾邮件** — `SPAM` 文件夹 + 阅读时「标记/移出垃圾邮件」(手动)。
   - **邮箱连通性检测** — 邮箱账户列表「测试连接」实测 SMTP/IMAP 授权码是否正确,`Crm::MailAccountVerifier`(腾讯企业邮 535 常见于授权码错)。
   - **写邮件防误关** — 点弹窗外不再关闭,「取消」有内容时二次确认,避免草稿丢失。
3. **销售资料 / 文档中心** — 同一 `KnowledgeDoc` 表,按 `library` 分:销售资料(SALES,可挂客户邮件)/ 文档中心(GENERAL,全公司)。看板拖拽改分类,右侧详情+时间轴。
4. **数据看板** — `Crm::StatsController` 一次聚合三页数据(KPI/目标/趋势/漏斗/客户来源/业务员排行/回复时长/完善度);Chart.js 面积/柱/环形图;company/mine 两口径。
5. **团队协同** — 内部 IM(真实头像+在线点、暗/浅气泡、单聊/群聊、已读回执名单、建群)。
6. **OA 审批** — 钉钉式审批(模板 + 多级流程 + 附件 + 部门/金额大写)。
7. **HR 组织人事** — 部门树与成员管理、部门负责人。
8. **成员权限** — 管理员给成员分配 CRM 角色(管理员/主管/业务员/无)。

---

## 权限模型（RBAC）

两层独立维度:

**① 能否进入 CRM**(入口门禁)
- `AccountUser#can_access_crm?` = 系统管理员 **或** 有 `crm_role`。
- `Crm::BaseController` 的 `before_action :ensure_crm_access` 对所有 CRM 接口做 403 门禁;前端路由守卫把无权用户重定向回工作台,侧边栏/工作台隐藏 CRM 入口。
- 其他部门成员(无 crm_role)照常用 OA/协同/文档中心/HR,进不去 CRM 销售。

**② 看得到谁的数据**(数据范围,`Crm::AccessScope`)
| 角色 | 可见范围 |
|---|---|
| 管理员 | 全部(`:all`) |
| 主管(manager) | 本人 + 所辖部门(含下级)全体成员 |
| 业务员(sales) | 仅本人 |

控制器用 `scope_by_owner(relation)` 过滤 `owner_id`(客户为 `account_owner_id`),越权访问自然 404。作用于客户/商机/邮件/订单/报价。

---

## 目录结构

```
app/
  models/{crm,chat,org}/*.rb
  controllers/api/v1/accounts/{crm,org,oa}/*.rb   # Crm::BaseController 为 CRM 基类
  services/crm/{access_scope,email_send_service,imap_fetch_service,email_intake_service}.rb
  jobs/crm/{send_email_job,fetch_imap_emails_job,recycle_stale_customers_job}.rb
  policies/crm/*_policy.rb
  listeners/crm_email_listener.rb
  views/api/v1/accounts/crm/**/*.jbuilder         # + models/_crm_*.json.jbuilder
  javascript/dashboard/
    routes/dashboard/crm/routes.js                # crm_* 路由 + meta(feature/permissions/library/requiresCrmAccess)
    routes/dashboard/crm/pages/*.vue              # 19 个页面
    stores/crm/*.js                               # Pinia(工厂 _crmStoreFactory)
    api/{crm,chat,org,oa}/*.js                    # ApiClient(工厂 _crmClient)
    components-next/CRM/*.vue                      # 建单/建客/写邮件等弹窗、图表
    components-next/sidebar/*                      # 定制侧边栏(玻璃 + 模块化 + 权限过滤)
config/
  routes.rb  (namespace :crm/:org/:oa)   schedule.yml (IMAP 收信 + 公海回收 cron)
db/migrate/2026*  (crm/chat/org/oa 相关迁移)
```

---

## 后端 API 命名空间

```
/api/v1/accounts/:account_id/
  crm/customers|opportunities|products|quotes|sales_orders|emails|
      knowledge_docs|knowledge_categories|mail_accounts|email_templates|
      sales_targets|teams|members|follow_up_notes|follow_up_tasks
  crm/stats  crm/team_dashboard  crm/my_target  crm/public_pool_settings
  org/departments  org/memberships
  oa/approval_templates  oa/approval_requests
  chat/conversations   (含 messages / read / counts)
/crm_email_open/:token   # 邮件打开追踪像素(公开,免登录)
```

---

## UI / 设计系统

- **冷调长春花玻璃质感(glassmorphism)**:app 外壳冷蓝渐变底 + 柔光光斑;磨砂玻璃侧边栏与页面面板(`bg-n-solid-1/55 backdrop-blur`);强调色 **iris(长春花)** 贯穿按钮/激活态/图表/KPI。
- **侧边栏**:无切换标签,按当前路由自动只显示所属系统的项;激活项为 iris 渐变胶囊;非 CRM 人员隐藏 CRM 分组、非管理员隐藏「设置」;隐藏原生客服模块(会话/收件箱/联系人/公司/报告/活动/帮助中心)。
- **颜色**:Radix `n-*` token(iris/blue/teal/ruby/slate…);金额一律 `*_micros` bigint + 币种字符串;枚举用字符串列 + 校验。
- 标签全中文。

---

## 本地开发与运行

Docker Compose(从源码构建,基础镜像 `chatwoot:development`):

```bash
docker compose up -d
# 新增迁移领先 schema.rb 时,显式跑:
docker compose exec rails bundle exec rails db:migrate db:seed
```
- 应用:http://localhost:3000  ·  邮件测试(mailhog):http://localhost:8025
- 登录(SuperAdmin):`john@acme.inc` / `Password1!`(account_id=1,CRM 已启用)
- 业务员测试账号示例:`sales@acme.inc` / `Sales@2026`(crm_role=sales)
- 前端由 vite 提供;改动后首个请求触发编译。

> `.env`、`docker-compose.yaml` 内含机器相关本地配置(pgdata 卷、SECRET_KEY_BASE、ActiveRecord 加密密钥),不提交。

---

## 代码约定

- 竖切交付:一个对象端到端(model→API→Vue→测试→浏览器验证),一 PR 一切片。
- 控制器镜像 `customers_controller`:继承 `Crm::BaseController` + `check_authorization → authorize(Crm::X)` + jbuilder partial `api/v1/models/_crm_x`。
- 金额 `*_micros`(与 Twenty 1:1,便于 ETL);枚举字符串列 + `inclusion` 校验 + `%w[]` 常量。
- i18n 仅改 `en/*.json`(本 fork 内填中文);Vue 一律组合式 `<script setup>`;Tailwind only,颜色查 `tailwind.config.js`。
- Commit 用 Conventional Commits,不引用 AI。
