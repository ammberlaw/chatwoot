# A-CRM · 外贸销售 CRM（Chatwoot 原生模块）

A-CRM 是一套面向**外贸/自营销售团队**的 CRM，作为原生模块内建在本 Chatwoot fork 中（Rails 7.1 + Vue 3）。
它由 [Twenty](https://twenty.com) 版 A-CRM（原 china-trade-crm）迁移重写而来，字段/业务口径沿用原规范，但**排版与前端 UI 已脱离 Twenty 原版面重做**。

- 需求规范（外部）：`/Users/amberlaw/acrm-migration/CRM_SPEC.md`
- 迁移目标：把 A-CRM 的能力用 Chatwoot 技术栈原生实现，AI 驱动开发。
- **用户使用指南**（面向最终用户，全中文）：[`docs/A-CRM用户使用指南.html`](docs/A-CRM用户使用指南.html)（浏览器打开或下载后查看）

---

## 目录结构

| 层 | 位置 |
|---|---|
| 后端控制器 | `app/controllers/api/v1/accounts/crm/` |
| 后端模型 | `app/models/crm/` |
| JSON 视图 | `app/views/api/v1/accounts/crm/`、`app/views/api/v1/models/_crm_*.json.jbuilder` |
| 前端页面 | `app/javascript/dashboard/routes/dashboard/crm/pages/` |
| 前端路由 | `app/javascript/dashboard/routes/dashboard/crm/routes.js` |
| 弹窗/组件 | `app/javascript/dashboard/components-next/CRM/` |
| 图表组件 | `app/javascript/dashboard/components-next/CRM/charts/` |
| Pinia stores | `app/javascript/dashboard/stores/crm/`（`_crmStoreFactory.js` 工厂） |
| 文案 i18n | `app/javascript/dashboard/i18n/locale/en/crm.json`（仅维护 en，其余语言由社区） |

前端调用统一走 `/api/v1/accounts/:accountId/crm/...`。数据以 **micros（金额×1e6 的整数）** 存储。

---

## 功能模块

### 1. 数据看板 `crm_dashboard_index`
`CrmDashboardIndex.vue` · 接口 `crm/stats`

一屏 **bento 布局**（脱离原 3-Tab），用真图表（Chart.js）：
- **KPI 行**：成交额 / 成交订单数 / 成交客户数 / 新成交客户数 —— MedFlow 式多色柔和渐变卡（黄→薄荷绿→蜜桃橙）
- **商机阶段漏斗**（柱状，柱端标金额、显示成交转化率）＋ **本月目标完成率半圆仪表**
- **订单金额趋势**（面积图）＋ **客户来源占比**（环形图 + 图例）
- **业务员成交排行**（横向柱）＋ **累计概览**（统计列表）
- **业务员平均回复时长 / 资料完善度**（横向柱）
- 顶栏：月/季/年切换（单个下拉随模式切内容：月份 / Q1–Q4 / 年份，换年真实重取），公司/我的口径。

### 2. 团队看板 `crm_team_dashboard_index`
`CrmTeamDashboardIndex.vue` · 接口 `crm/team_dashboard`

按团队查看本月成交额 / 新成交客户，团队合计进度条 + 成交额完成率半圆仪表，组员完成率双列卡片。

### 3. 我的目标 `crm_my_target_index`
`CrmMyTargetIndex.vue` · 接口 `crm/my_target`、`crm/sales_targets`

个人目标：**未完成结转下月、超额顺延、每季度清零**（前端实时算）；聚焦月卡片 + 达成半圆仪表 + 12 个月明细表 + 就地设定/修改基础目标。

### 4. 客户（私海/公海）`crm_customers_index`
`CrmCustomersIndex.vue` · 控制器 `customers` · 模型 `Crm::Customer`

- 卡片式表格（圆角+阴影），完善度评分、状态、级别、来源、贸易国家/地区等标签字段。
- **筛选**：全部/我的/私海/公海/未分配 + 客户名搜索(`q`) + **admin 团队 → 业务员**逐级筛选(`team_id`/`account_owner_id`) + 客户分组 + 产品分组；分页。
- **排序**：点「累计成交额」表头切换 倒序/正序（后端 `sort`+`direction` 白名单列，`COALESCE(列,0)` 处理 NULL）。
- **认领**（公海→私海）/ **转公海**；分组私海上限由模型校验。
- **右侧详情面板**（点行展开，Twenty 风格，编辑仍走弹窗）：
  - 字段分组 + 头像/创建时间 + 底部编辑/认领/转公海。
  - **标签页**：主页(字段) / **操作历史**(审计日志) / 备注 / 文件 / 电子邮件；按需加载(`?customer_id=`)。
  - **操作历史 = 审计**：`Crm::Customer` 启用 `audited`（排除成交统计/时间戳），`GET crm/customers/:id/audits` 返回"谁/动作/改了哪些字段/时间"，前端渲染成中文操作流（重新分配 / 编辑了客户信息 …）。
  - 文件走客户 `has_many_attached :files` + attach/detach；备注/邮件走 `follow_up_notes`/`emails` 的 `customer_id` 过滤。
- ⚠️ `api/crm/customers.js` 的 `get` 需透传全部查询参数（曾只传 page/filter/status → 导致搜索/排序/筛选静默失效，已修）。

### 5. 客户建档 `crm_customer_intake_index`
`CrmCustomerOnboardingIndex.vue` · 控制器 `customers#check_duplicate`

新建客户引导页：**实时查重**（邮箱精确命中阻止 + 公司名相似提醒），建档自动归私海。

### 6. 商机看板 / 商机列表
`crm_funnel_index` `CrmOpportunityFunnelIndex.vue` · `crm_opportunities_index` `CrmOpportunitiesIndex.vue`
控制器 `opportunities` · 模型 `Crm::Opportunity`（阶段：NEEDS_CONFIRMED / SAMPLING / WON / LOST）

- **商机看板**（原「商机漏斗看板」已改名「商机看板」）：kanban 四列，**拖拽换阶段**；列头显示数量 + 总金额（带货币符号）。
- **卡片**：● 阶段颜色小圈 + 商机名 / 🏢客户 / 备注 / 分隔线 / 金额 · 概率；**点卡直接编辑**。
- **+新建商机**（入口从列表移到看板）。
- **admin 逐级筛选**：团队 → 业务员（后端 `team_id` 按团队成员过滤、`owner_id` 精确到人）。
- 新建/编辑弹窗：**关联私海客户可搜索下拉**（输入名字按 `q` 搜索、限私海）、暖橙确认按钮、纯中文标签。

### 7. 销售订单 `crm_sales_orders_index`
`CrmSalesOrdersIndex.vue` · 控制器 `sales_orders` · 模型 `Crm::SalesOrder`

订单列表（状态筛选 + 分页）；订单按 owner 自动反写所属团队（`crm_team_id`）。

### 8. 销售目标 `crm_sales_targets_index`
`CrmSalesTargetsIndex.vue` · 控制器 `sales_targets` · 模型 `Crm::SalesTarget`

按月设定目标成交额/新客户数（个人 = 自己的，公司 = 全员合计）。

### 9. 报价与明细
控制器 `quotes` / `quote_line_items` · 模型 `Crm::Quote` / `Crm::QuoteLineItem` · 产品 `products` / `Crm::Product`

商机报价与行项目、产品库（供报价选品）。

### 10. 知识库 `crm_knowledge_docs_index`
`CrmKnowledgeDocsIndex.vue` · 控制器 `knowledge_docs` · 模型 `Crm::KnowledgeDoc`

产品目录/资质/手册/报价模板等文档，**支持附件上传/下载**（ActiveStorage `has_many_attached :files`，attach/detach 成员路由）、分类筛选、标题/摘要搜索、分页、查看/编辑。

### 11. 邮件中心
- 收发邮件 `crm_emails_index` `CrmEmailsIndex.vue` · 控制器 `emails` · 模型 `Crm::Email`
- 邮件模板 `crm_email_templates_index` · 控制器/模型 `email_templates`
- 发信邮箱 `crm_mail_accounts_index` · 控制器/模型 `mail_accounts`
- 写邮件弹窗 `CrmEmailComposeDialog.vue`

每个业务员配置自己的企业邮箱（SMTP + 授权码）；发件走 `Crm::EmailSendService` / `Crm::SendEmailJob`；收件由 `message_created → AsyncDispatcher → CrmEmailListener`（Sidekiq）经 `Crm::EmailIntakeService` 入库（通知域过滤、`chatwoot_message_id` 去重、联系人→客户关联）。本地用 mailhog（SMTP `:1025` / HTTP `:8025`）测试收发。

### 12. 团队 / 跟进
- 团队 `teams` · 模型 `Crm::Team`（`has_many :members through account_users`，业务员经 `account_users.crm_team_id` 归属团队）
- 跟进记录/任务 `follow_up_notes` / `follow_up_tasks`
- 联系人 `contacts`、公海规则 `public_pool_settings`

### 13. 绩效考核（KPI）
控制器 `kpi_schemes` / `kpi_sheets` / `employee_comps` / `performance_settings` · 模型 `Crm::KpiScheme(+SchemeItem+PayoutTier)` / `Crm::KpiSheet(+Item)` / `Crm::EmployeeComp` / `Crm::PerformanceSetting`

- **考核方案**：月度可编辑（指标/权重/发放系数档），下发后每人一张考核表；列表带**年份归档筛选**。
- **考核表**：五步流转 待填报→已提交→已打分→人事确认→归档（四方电子签）；`recompute_payout!` 按总分→系数档→实发绩效（月薪×绩效占比）。列表带**搜索（业务员/方案名）+ 月份 + 状态筛选**。
- **数据范围**：超管/管理员/指定人事/总经理看全部；部门负责人看本部门（含下级）；业务员只看自己（实发金额敏感）。
- **员工薪资配置**（敏感区，二次验证）与**审批人设置**（指定人事/总经理 + 板块角色可见性开关）。

### 14. 员工档案（员工主数据）`crm_employees_index`
`CrmEmployeesIndex.vue` · 控制器 `employees` · 模型 `Crm::Employee` · 独立 HR 板块（超管/管理员）

- **在职 / 试用 / 离职**分组页签 + 姓名/工号/手机号搜索；六板块建档表单：基本身份（工号唯一、证件照 `photo`、入职资料 `entry_files`）/ 岗位组织（部门、**关联系统账号 `user_id`**）/ 状态与关键日期（工龄自动算）/ 薪酬发薪 / 联系方式 / 离职信息（`resign_files`）。
- **离职交接** `Crm::OffboardingService`：状态改「离职」时触发——客户/商机**退回公海**（默认）或 `handover_target_id` 转移；个人文档 `discard!` 进回收站；账号 `crm_role` 置空。只在非离职→离职转换时执行一次。
- 删号兜底：`AccountUser#after_destroy` 也会归档个人文档。

### 15. 权限与安全体系

- **系统角色**（成员权限页一个下拉）：超级管理员 `administrator` / 管理员 `deputy_admin` / 部门负责人 `manager` / 业务员 `sales` / 无。数据范围见 `Crm::AccessScope`（超管、管理员=全部；负责人=部门子树；业务员=本人）。**统一口径：管理员=超管减去「任免/修改超级管理员」**（组织架构维护、文档回收站、审批模板维护均已放开给管理员）。
- **防提权**：管理员不可任免/改动超级管理员、不可发超管邀请（`members`/`member_invites` 控制器拦截 + 前端选项过滤）。
- **负责人联动**：`Org::Department` 设/卸 `leader_id` 自动同步 `crm_role`（manager ↔ sales，超管/管理员不动）。
- **模块开关** `account_users.module_access`（CRM/ERP/MES）；ERP、MES 未上线在 UI 置灰。
- **敏感区二次验证** `Crm::SensitiveSession`（Redis 15 分钟）：员工档案/薪资配置需重输登录密码，后端 `ensure_sensitive_session` 403 兜底。
- **脱敏**：身份证/银行卡默认打码点「显示」展开；薪资金额 `¥ ******` 页头开关。
- **审计与留痕**：`audited`（改动字段级审计）+ `Crm::AccessLog`（list/view 查看日志），员工档案编辑页有合并「操作历史」时间轴。
- **密码集中管控**：自改密码（个人资料 + 忘记密码邮件）仅限超管/管理员/行政部门成员（`AccountUser#password_self_service?`）；超管/管理员可在成员权限改成员姓名/邮箱/重置密码；**部门负责人**限下属、仅重置密码（`manager_overreach?`）。
- **审批模板维护** `oa_template_maintainer?`：超管/管理员或行政部门成员（部门名含「行政」，含下级）。

### 16. 考勤 `crm_attendance_index`
`CrmAttendanceIndex.vue` · 控制器 `attendances` / `attendance_groups` · 模型 `Crm::AttendanceRecord` / `Crm::AttendanceGroup`

- **打卡**：上班/下班两次打卡（重复打取更晚时间），服务器按 `Asia/Shanghai` 时区判定 正常/迟到/早退/迟到+早退；每人每天一条（唯一约束）。
- **我的考勤**（全员）：月历视图 + 月度统计；过去的工作日无记录=缺卡。
- **考勤汇总**：超管/管理员全员、部门负责人本部门（含下级）；出勤/迟到/早退/缺卡/请假计数。
- **HR 修正**（超管/管理员）：给某人某天直接定状态（可补建记录），`adjusted_by` 留痕 + `audited` 审计；修正后不再被打卡自动改写。
- **考勤组**（超管/管理员）：多组规则——每组独立的工作日/上下班时间/宽限/节假日/成员（不同部门不同作息）；一人一组（分配时自动从其他组移除），未分组成员按「默认考勤组」执行（默认组不可删）。
- **补卡规则**（按组）：`reclock_limit` 每月补卡上限（0=不允许）、`reclock_window_days` 可补时限天数（0=不限）；提交补卡审批时按申请人所属组校验（时限/上限/不可补未来）。
- **审批联动** `Crm::AttendanceApprovalService`：审批模板可标记 `attendance_kind`（leave 请假单 / reclock 补卡申请）；整单通过时自动写考勤——请假取表单日期字段最早/最晚为区间逐工作日标「请假」，补卡取第一个日期补「正常」；等同 HR 修正（adjusted_by=终审人）。
- **节假日**：按考勤组维护日期数组；节假日不计工作日/缺卡。
- 全员可用（`skip ensure_crm_access`）。

### 17. 团队沟通（群聊）`crm_team_chat_index`
`CrmTeamChatIndex.vue` · 控制器 `chat/conversations`

- 单聊/群聊、文件附件、已读名单；**建群必填群公告**，公告更新推送「【群公告】」消息。
- 群主（`creator_id`）可编辑公告、踢人、**转让群主**（`transfer_owner`，推送变更消息）；成员可**退群**（`leave`），群里还有人时群主必须先转让。

---

## 图表组件（Chart.js 封装）

`components-next/CRM/charts/`（依赖项目自带 `chart.js@4.4` + `vue-chartjs@5.3`）：
- `CrmAreaChart.vue` —— 平滑面积图 + 渐变填充
- `CrmBarChart.vue` —— 柱状/横向柱，支持柱端数值标签
- `CrmDoughnutChart.vue` —— 环形图 & 底部半圆仪表（`gauge` prop）
- `chartColors.js` —— `themeColor()` 从 CSS 变量读色，**随明暗主题自适应**；`chartPalette()` 常用色板

---

## 设计语言（当前定稿）

- **主色暖橙 `amber`**（试过 teal 绿 / violet 紫，最终定 MedFlow 暖橙），单色 + 中性灰克制风。
- 卡片 `rounded-2xl` + 柔和阴影，大标题（`text-2xl font-semibold`），胶囊分段切换，`focus-visible` 焦点环。
- KPI 卡 = **多色柔和渐变**（`CARD_GRADIENTS` 字面量数组）。
- 语义色：涨=teal 绿 / 跌=ruby 红；完成率分档 绿/蓝/橙/红。
- 全程 Tailwind + radix `n-` token，无自定义 CSS、无硬编码色。改色可"一把梭" sed 替换。
- 参考：`Dialog` 组件新增可选 `confirmButtonColor` prop（默认不变，向后兼容）。

---

## 本地开发 / 运行

- 栈：docker split 容器 `chatwoot-rails-1` / `chatwoot-vite-1` / `chatwoot-postgres-1` / `chatwoot-sidekiq-1` / `chatwoot-mailhog-1`。
- 前端 vite dev（`/vite-dev/` 代理）；改完 UI **硬刷新 `Cmd+Shift+R`** 看效果。
- Lint：`node_modules/.bin/eslint`（150 字符行宽、Airbnb+Vue3）；Ruby `bundle exec rubocop`（AbcSize 26 / Cyclomatic 7）。
- 提交因 husky 钩子缺 lint-staged，需 `git commit --no-verify`。
- i18n 只维护 `en.json` / `en.yml`。
- 铺样本示例（rails runner）：见「商机样本」——按团队成员当负责人、关联真实客户，覆盖四阶段/多币种。

## 前端路由名

`crm_dashboard_index` · `crm_team_dashboard_index` · `crm_my_target_index` · `crm_customers_index` · `crm_customer_intake_index` · `crm_opportunities_index` · `crm_funnel_index` · `crm_sales_orders_index` · `crm_sales_targets_index` · `crm_knowledge_docs_index` · `crm_doc_center_index` · `crm_emails_index` · `crm_email_templates_index` · `crm_mail_accounts_index` · `crm_org_structure_index` · `crm_members_index` · `crm_member_invites_index` · `crm_employees_index` · `crm_employee_comps_index` · `crm_attendance_index` · `crm_kpi_schemes_index` · `crm_kpi_sheets_index` · `crm_performance_settings_index` · `crm_approvals_index` · `crm_approval_templates_index` · `crm_team_chat_index` · `crm_workspace_index`

> 注意：SPA 路由名含 `onboarding_` 会被账号引导守卫劫持重定向到 dashboard，CRM 页路由名需避开该串。
