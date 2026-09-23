# wintouchspace App — MES 生产模块交接书

> 接着现有 App 往下做。CRM 部分已经做完了，这一轮只做 **MES 生产**。
> **ERP 财务保持现状不动**（继续用 `ModulePlaceholderPage.vue` 占位）——ERP 后端还没部署到生产服务器，
> 现在做出来装到手机上就是 404。

---

## 0. 一句话范围

把 MES 里**必须在现场/路上完成**的那几件事搬上手机：**审批、接单、报工、查库存、出库、通知**。
电脑上才干得了的活（做 BOM、建采购单、维护主数据、产品档案、序列号）**这一轮不做**，点进去仍是占位页。

判断标准：**这件事是不是必须站在车间/仓库/客户现场，或者在没电脑的时候做？** 是才上手机。

---

## 1. 代码位置与既有约定

代码在 `mobile/`，Vue 3 `<script setup>` + Vite + Tailwind + Capacitor 8（iOS WKWebView）。
**先读这三个文件再动手**，新页面的写法照抄它们，不要另起一套：

| 文件 | 看什么 |
|---|---|
| `src/pages/ApprovalsPage.vue` | 列表页标准写法：分段切换 + 分页加载 + `DataState`/`EmptyState` + 离线态 |
| `src/api/crm.js` | 接口薄封装的写法（`base()` 拼 accountId，页面不碰 URL） |
| `src/api/client.js` | 鉴权、`cachedGet` 离线缓存、401 处理——**已经做好了，别改** |

可直接复用的组件：`PageHeader` / `LargeTitleBar` / `IosSegmented` / `IosRow` / `AppSheet` /
`DataState` / `EmptyState` / `PullToRefresh` / `FormField` / `AttachmentField` / `OfflineNotice`。

视觉规范见 `UI_BRIEF.md`（黑白灰 + 品牌黄，黄不写字；深浅两套都要）。**MES 页面不另开一套视觉。**

### 新增文件

```
src/api/mes.js                    ← 新建，MES 所有接口的薄封装
src/constants/mes.js              ← 新建，阶段/状态/通知类型的中文映射
src/pages/mes/MesHomePage.vue     ← 以下 P0/P1 页面
src/pages/mes/MesTodoPage.vue
src/pages/mes/MesOrdersPage.vue
src/pages/mes/MesOrderDetailPage.vue
src/pages/mes/MesReportPage.vue
src/pages/mes/MesStockPage.vue
src/pages/mes/MesShipmentsPage.vue
src/pages/mes/MesNotificationsPage.vue
```

路由全部挂在 `/mes/*` 下（`router/index.js`）。**把现有 `/mes` 那条占位路由换成 `MesHomePage`，
`/erp` 那条原样保留。**

---

## 2. 接口通则

- 基址：`/api/v1/accounts/{accountId}/mes/...`，`accountId` 从 `useAuthStore().accountId` 取。
- 鉴权：`access-token` / `client` / `uid` 三个连字符请求头，`client.js` 的拦截器已自动带上。
  ⚠️ **不要用 `api_access_token`**——生产 nginx 会把带下划线的请求头丢掉。
- 列表响应统一是 `{ meta: { count, current_page }, payload: [...] }`；
  少数接口（`inbox`、`unread_count`、`stock_balances`）是 `{ payload: ... }` 没有 meta。
- 分页参数是 `page`。**`per_page` 只有生产订单列表认**，其余接口固定每页 15 条，别传了指望它生效。
- 产品线：MES 数据按产品线分流。带 `product_line` 参数过滤，值是
  `COMMERCIAL_DISPLAY`（商显工控）/ `TABLET`（平板电脑），**不传 = 全部产线**。
  手机端**默认不传**（看全部）；在 MES 首页右上角放一个切换器，选中值存 `Preferences`，
  由 `api/mes.js` 统一注入，页面不要各自传。
- 出错时后端返回 `{ error: "中文原因" }`（422/403）。**这些文案是给人看的，直接弹出来，别自己编。**

---

## 3. 准入与权限（做之前先把这段读完）

登录响应 `/auth/sign_in` 里的 user 对象已经带齐了判断依据，**不需要再调接口**：

```jsonc
{
  "role": "agent | administrator",
  "crm_role": "deputy_admin | manager | sales | hr | null",
  "mes_roles": ["pmc" | "engineer" | "buyer" | "warehouse" | "production"],  // 多值，可兼岗
  "mes_capabilities": ["order","bom","purchase","stock","report","shipment","quality","master","product"],
  "module_access": ["crm","mes",...]
}
```

规则：

1. **能不能进 MES 模块**：`module_access` 含 `mes`，或 `role === 'administrator'`。
   进不去的人，工作台上那张 MES 大卡**直接不渲染**（不是灰掉也不是点了报错）。
2. **能不能做某个操作**：看 `mes_capabilities` 里有没有对应能力域。
   写一个 `mesCan(domain)` 放在 `src/composables/useMesRole.js`，管理员恒 true。

| 能力域 | 谁有 | 手机上管什么 |
|---|---|---|
| `order` | PMC、工程 | 生产订单的改 |
| `report` | 生产（车间） | **报工** |
| `stock` | 仓管 | 入库/领料过账 |
| `shipment` | 仓管 | **执行出库** |
| `quality` | 仓管、生产 | 质检 |
| `purchase` | 采购 | 采购单 |
| `bom` / `master` / `product` | 工程、PMC / 采购 | 本轮手机端不做 |

3. **审批权不看能力域**，后端按「是不是本单指定审批人」判，前端拿到什么就显示什么：
   审批列表接口本身只返回「该我批的」，**不要再自己过滤一遍**。
4. 🔴 **硬约束，不能破**：销售端绝不可见**成本、供应商、毛利**。
   后端已经按 `mes_staff?` 收口了——纯业务员拿到的 `purchase_orders` 是空数组、
   `outsource_supplier_name` 不下发。**前端不要自作主张补展示、不要从别处凑这些字段。**
   业务员看得到的只有阶段名和进度，看不到钱和供应商。

---

## 4. 业务背景：8 阶段生产流水线

一张生产订单从头到尾会走这 8 个阶段，顺序固定，不能跳：

```
SALES_CONFIRMED  销售订单确定 →  BOM_READY  工程/PMC BOM  →  PURCHASING  采购原料
→ MATERIAL_INBOUND 原料入库 → PICKING 生产领料 → PRODUCTION 生产
→ FG_INBOUND 成品入库 → SHIPPED 销售出库
```

阶段中文名（`src/constants/mes.js` 照抄，注意第一个是**「待工程接单」**不是「销售订单确定」）：

```js
export const STAGE_LABELS = {
  SALES_CONFIRMED: '待工程接单',
  BOM_READY: '工程/PMC BOM',
  PURCHASING: '采购原料',
  MATERIAL_INBOUND: '原料入库',
  PICKING: '生产领料',
  PRODUCTION: '生产',
  FG_INBOUND: '成品入库',
  SHIPPED: '销售出库',
};
```

两个关键机制，手机端要如实体现：

- **接单确认（反推诿）**：订单流到你负责的阶段，你得先「接单」表示认领。超时不接会标红。
  字段 `awaiting_ack`（待接单）/ `ack_overdue`（超时未接）/ `ack_deadline`（截止时间）。
- **审批取代发布**：生产订单是「草稿 → 提交 → 部门主管批 → 总经理批 → 生效」。
  `approval_status`：`DRAFT / SUBMITTED / MANAGER_APPROVED / APPROVED / REJECTED`。
  只有 `APPROVED` 的单才会进流转、才被下游看见。

另外有一条**不走生产线**的旁路，手机端要做（见 §5 的出库页）：
**现货直发出库** = 成品库有货，业务员直接开单卖 → 部门主管审 → 仓库出库。
`Mes::Shipment.kind`：`PRODUCTION`（自产出库）/ `STOCK`（现货直发）。
STOCK 单状态：`PENDING_APPROVAL → APPROVED → SHIPPED`，驳回是 `REJECTED`。

---

## 5. 页面清单

### P0 — 这一轮的核心，必须做完

#### 5.1 MES 首页 `MesHomePage.vue` `/mes`

进 MES 的总入口，取代现在的占位页。从上到下：

1. `LargeTitleBar` 标题「MES 生产」+ 右上角产品线切换器（全部产线 / 商显工控 / 平板电脑）
2. **我的待办卡**（最重要，放第一屏）：三个数字并排 —— 待我审批 / 待我接单 / 待我审核出库，
   合计数在 MES 卡角标上。点进去是 §5.2。数字为 0 时该项显示灰色，不隐藏。
3. **在产概览**：`in_production` 一个大数 + 阶段分布（8 个阶段各多少单，横向条）。
   ⚠️ 手机上**不要画图表库**，用等宽的 div 条 + 数字就够。
4. **预警**：`overdue`（已逾期）/ `due_soon`（临期）/ `stalled`（滞留）/ `unacked`（超时未接单）
   四个数，有值的才显示，`overdue` 和 `unacked` 用红色点标记。
5. 底部一行入口：生产订单 / 报工 / 库存 / 出库 / 通知（按权限显隐）。

接口：`GET /mes/dashboard`（KPI+预警）、`GET /mes/notifications/unread_count`（角标）、
以及 §5.2 那三个 inbox 接口（只取 length 做数字）。

#### 5.2 我的待办 `MesTodoPage.vue` `/mes/todo`

三段式（`IosSegmented`），每段一个列表：

**① 待我审批**（生产订单）`GET /mes/production_orders/approval_inbox`
- 每行：工单号 + 成品名 + 数量 + 提交人 + 提交时间 + 交期
- 两个按钮：**通过** `POST /mes/production_orders/{id}/approve`（可选 `comment`）
  / **驳回** `POST /mes/production_orders/{id}/deny`（**`reason` 必填**，走 `AppSheet` 让用户填）
- 后端会按当前环节（主管/总经理）自动判定，前端不用管是第几级

**② 待我接单** `GET /mes/production_orders/inbox`
- 返回的是「停在我负责阶段上的在产订单」，每行给
  `{ id, order_no, product_name, stage, awaiting_ack, ack_overdue, ack_deadline, entered_at }`
- 显示：工单号 + 成品名 + **阶段中文名** + 已停留天数（由 `entered_at` 算）
- `ack_overdue` 为 true 的行：左侧一道红色竖条 + 「超时未接单」标签，**排在最前**
- 两个按钮：**接单** `POST /mes/production_orders/{id}/acknowledge`
  / **退回上一环节** `POST /mes/production_orders/{id}/reject`（**`reason` 必填**）
- 已接单（`awaiting_ack` false）的行，按钮换成「去操作」→ 跳对应页面：
  `PRODUCTION` → 报工页（带工单号预筛）；`FG_INBOUND`/`MATERIAL_INBOUND`/`PICKING` → 本轮没做对应
  操作页，跳订单详情即可，**不要跳到空白路由**

**③ 待我审核出库** `GET /mes/shipments/approval_inbox`
- 现货出库单，每行：出库单号 + 客户名 + 明细件数 + 开单人 + 提交时间
- 按钮：**通过** `POST /mes/shipments/{id}/approve` / **驳回** `POST /mes/shipments/{id}/reject`（`reason` 必填）

三个接口都不分页，一次拉完。三段的数字显示在分段控件上。
**下拉刷新**必须有（`PullToRefresh`），批完一单就地从列表移除、数字减一，不要整页重载。

#### 5.3 通知 `MesNotificationsPage.vue` `/mes/notifications`

`GET /mes/notifications`（`page`；`unread=true` 只看未读）→
`{ meta: { count, current_page, unread_count }, payload: [{ id, kind, title, body, read_at, production_order_id, order_no, created_at }] }`

- 未读的行：标题加粗 + 左侧一个小黄点；已读常规
- 点击 → `POST /mes/notifications/{id}/mark_read`，有 `production_order_id` 的跳订单详情
- 顶部「全部已读」→ `POST /mes/notifications/mark_all_read`
- `kind` 的中文映射放 `constants/mes.js`：

```js
export const NOTIFICATION_LABELS = {
  approval_pending: '待审批',        approval_approved: '审批通过',      approval_rejected: '审批驳回',
  bom_reconfirm: 'BOM 待确认',       bom_confirmed: 'BOM 已确认',        bom_revised: 'BOM 已变更',
  purchase_release_pending: '待下发采购', stage_assigned: '流转到你',      stage_returned: '被退回',
  po_approval_pending: '采购单待审批', po_approval_approved: '采购单通过',  po_approval_rejected: '采购单驳回',
  order_revised: '订单已修改',        production_reported: '有新报工',     fg_count_pending: '待清点入库',
  shipment_approval_pending: '出库待审核', shipment_approved: '出库已通过',  shipment_rejected: '出库被驳回',
  document_returned: '单据被退回',    forwarded: '有人知会你',
};
```

---

### P1 — 核心做完接着做

#### 5.4 生产订单列表 `MesOrdersPage.vue` `/mes/orders`

`GET /mes/production_orders`，参数：`page` / `per_page`（这个接口认 per_page）/ `q`（搜工单号、成品名、商品编码）/
`stage` / `status` / `list_scope`（`mine` 只看我的按单 / `stock` 只看备货）/ `product_line`

- 顶部搜索框 + 阶段筛选（`AppSheet` 里选，8 个阶段 + 全部）
- 每行：工单号 / 成品名 / 客户名 / 数量 + 已产量 + 进度条（`progress_ratio`）/ **阶段中文名** / 交期
- `ack_overdue` 的单标红点；`is_draft` 的单打「草稿」灰标
- 点行进详情。**手机端只读，不做新建和编辑**（建单要填一整套 spec 模板，手机上填不了）

#### 5.5 生产订单详情 `MesOrderDetailPage.vue` `/mes/orders/:id`

`GET /mes/production_orders/{id}`，字段很全（见 §6 的字段表）。分几段：

1. **头部**：工单号 + 成品名 + 阶段中文名 + 状态标签
2. **进度条**：8 阶段横向走势，已过的实心、当前的黄色高亮、未到的灰。
   当前阶段下面一行小字：**「等谁」**（`stage_owner_names`）+ **「卡了几天」**（由当前阶段的
   `stage_events` 里最后一条 `entered_at` 算）
3. **接单区**：`awaiting_ack` 为 true 且当前用户在 `stage_owner_ids` 里 → 显示接单/退回按钮
4. **基本信息**：客户 / 销售订单号 / PI 号 / 数量+单位 / 已产量 / 交期 / 归属业务员 / 商品编码
5. **审批链**：`approval_status` + 主管姓名与意见 + 总经理姓名与意见（有才显示）
6. **材料明细**（`bom_items`，详情才有）：料号/名称/规格/单位/数量，**表格横向可滚动**
7. **图片与附件**：`images` / `files`，图片九宫格可点开大图（URL 是相对路径，要拼 `API_BASE`）
8. **时间线**：`stage_events` 逐条，阶段中文名 + 进入时间

🔴 **`purchase_orders` 字段对业务员是空数组，这是故意的。空就不渲染那一段，不要提示「无权查看」**——
不要让销售端意识到有这块东西。

#### 5.6 生产报工 `MesReportPage.vue` `/mes/report`

车间现场用，**这页是手机端价值最高的一页**，要能单手快速完成。

- 列表：`GET /mes/production_records`（`page`、`production_order_id` 可筛）
  每行：工单号 + 成品名 + 工序 + 完成数 + 报工人 + 报工时间
- 新建（限 `mesCan('report')`）：`POST /mes/production_records`
  ```jsonc
  { "production_record": {
      "production_order_id": 123, "operation_name": "组装", "qty_completed": 50,
      "qty_returned": 0, "qty_scrap": 2, "recorded_at": "2026-09-19T14:00:00+08:00", "remark": "" } }
  ```
  - 工单从「待我接单/在产订单」里选（列表下拉 + 搜索），**不要让人手打工单号**
  - 数量用大号数字键盘（`inputmode="numeric"`），`qty_completed` 必填
  - `recorded_at` 默认当前时间，可改
  - 报工成功后弹一句「已报工 N 件」，列表置顶插入新行
- **首次报工会把订单从 PICKING 推进到 PRODUCTION**，这是后端自动的，前端不用管，
  但报工成功后要刷新一下订单相关的数字

#### 5.7 库存结存 `MesStockPage.vue` `/mes/stock`

`GET /mes/stock_balances`，参数 `item_type`（`MATERIAL` 物料 / `PRODUCT` 成品）/ `warehouse_id` /
`short=true`（只看低于安全库存的）/ `product_line`。**不分页，一次全返回**，前端做搜索过滤。

- 顶部分段：成品 / 物料；搜索框按名称或编码过滤
- 成品行显示三个数：**结存 `qty` / 预占 `reserved_qty` / 可用 `available_qty`**
  （预占 = 已提交待出库的单占着的量。业务员看「可用」那一列决定能不能卖）
- 物料行显示：结存 + 安全库存，`is_short` 为 true 的标红
- 这页是纯查询，**全员可读，不需要能力判断**

---

### P2 — 前面做完再说，可以单独一轮

#### 5.8 销售出库 `MesShipmentsPage.vue` `/mes/shipments`

`GET /mes/shipments`（`page` / `status` / `kind` / `product_line`）

三类人在这页干三件不同的事，按 `mes_capabilities` 和单据状态显示按钮：

| 谁 | 看到什么 | 干什么 |
|---|---|---|
| 业务员 | 自己开的现货单 | **新建现货出库**；被驳回的单改完 `POST /{id}/submit` 重提 |
| 部门主管 | 待我审核的单 | 通过 / 驳回（和 §5.2 ③ 同一套接口） |
| 仓管（`mesCan('shipment')`） | 已审核待出库的单 | **出库** `POST /{id}/ship` |

新建现货出库 `POST /mes/shipments`：
```jsonc
{ "shipment": {
    "kind": "STOCK", "crm_customer_id": 12, "crm_sales_order_id": 34, "warehouse_id": 2, "remark": "",
    "shipment_items_attributes": [ { "crm_product_id": 88, "qty": 10, "unit": "台" } ] } }
```
- 成品从产品档案选（`GET /mes/products`，全员可读），**选的时候必须显示该成品的「可用现货」**
  （从 `stock_balances` 取 `available_qty`），可用为 0 的不让选
- 建单即提交审核，后端会校验可用量，**不够会直接 422 返回「可用 34，需 38」这种文案，原样弹出来**
- 出库时库存不足也会 422 列出缺口，同样原样弹

状态中文：
```js
export const SHIPMENT_STATUS_LABELS = {
  DRAFT: '草稿', PENDING_APPROVAL: '待审核', APPROVED: '待出库',
  SHIPPED: '已出库', REJECTED: '已驳回',
};
```

---

## 6. 生产订单详情的字段表

`GET /mes/production_orders/{id}` 返回（挑手机端要用的）：

| 字段 | 含义 |
|---|---|
| `order_no` / `pi_no` / `sales_order_no` | 工单号 / PI 号 / 关联销售订单号 |
| `product_name` / `product_sku` / `product_code` | 成品名 / 商品编码 / 产品编码 |
| `customer_name` / `customer_country` | 客户 / 国家 |
| `qty` / `unit` / `produced_qty` / `progress_ratio` | 计划量 / 单位 / 已产量 / 进度（0~1） |
| `stage` / `stage_events[]` | 当前阶段 / 阶段流转记录 `{stage, entered_at, note}` |
| `stage_owners[]` / `stage_owner_names[]` / `stage_owner_ids[]` | 当前阶段负责人 |
| `awaiting_ack` / `ack_overdue` / `ack_deadline` / `stage_ack_at` / `stage_ack_by_name` | 接单状态 |
| `status` | `IN_PROGRESS / COMPLETED / STOPPED / CANCELLED` |
| `order_kind` | `CUSTOMER` 按单 / `STOCK` 备货 |
| `approval_status` / `manager_name` / `manager_comment` / `gm_name` / `gm_comment` | 审批链 |
| `delivery_date` / `planned_*_date` / `actual_*_date` | 交期与计划/实际起止 |
| `owner_id` / `owner_name` | 归属业务员 |
| `bom_no` / `bom_items[]` | BOM 单号 / 材料明细（仅详情） |
| `images[]` / `files[]` | `{id, filename, url}`，url 是**相对路径**，要拼 `API_BASE` |
| `spec` | 定制规格 jsonb，字段随产品线变 —— **手机端按 key/value 平铺展示就行，不要写死模板** |
| `remark` | 备注 |
| `purchase_orders[]` | 🔴 业务员恒为空数组，空就不渲染 |

状态中文：
```js
export const ORDER_STATUS_LABELS = {
  IN_PROGRESS: '在产', COMPLETED: '已完成', STOPPED: '已暂停', CANCELLED: '已取消',
};
export const APPROVAL_STATUS_LABELS = {
  DRAFT: '草稿', SUBMITTED: '待主管审批', MANAGER_APPROVED: '待总经理审批',
  APPROVED: '已生效', REJECTED: '已驳回',
};
```

---

## 7. 完整接口清单

前缀一律 `/api/v1/accounts/{accountId}/mes`。

### 待办与审批
```
GET   /production_orders/approval_inbox          待我审批（生产订单）
POST  /production_orders/{id}/approve            通过     body: { comment? }
POST  /production_orders/{id}/deny               驳回     body: { reason }  必填
GET   /production_orders/inbox                   待我接单（{payload:[...]}，无 meta）
POST  /production_orders/{id}/acknowledge        接单
POST  /production_orders/{id}/reject             退回上一环节  body: { reason }  必填
GET   /shipments/approval_inbox                  待我审核（现货出库）
POST  /shipments/{id}/approve                    通过
POST  /shipments/{id}/reject                     驳回     body: { reason }  必填
```

### 看板与通知
```
GET   /dashboard                                 KPI + 阶段分布 + 预警
GET   /notifications                             ?page=&unread=true
GET   /notifications/unread_count                { payload: { unread_count } }
POST  /notifications/{id}/mark_read
POST  /notifications/mark_all_read
```

### 生产订单
```
GET   /production_orders                         ?page=&per_page=&q=&stage=&status=&list_scope=&product_line=
GET   /production_orders/{id}                    详情（含 bom_items / forward_targets）
```

### 报工
```
GET   /production_records                        ?page=&production_order_id=
POST  /production_records                        body: { production_record: {...} }
DELETE /production_records/{id}                  删报工会回退已产量；有成品入库时后端会拒绝
```

### 库存与出库
```
GET   /stock_balances                            ?item_type=&warehouse_id=&short=true   不分页
GET   /warehouses                                仓库下拉
GET   /products                                  产品档案（全员可读），?q= 搜索
GET   /shipments                                 ?page=&status=&kind=
POST  /shipments                                 新建现货出库
POST  /shipments/{id}/submit                     被驳回后重新提交
POST  /shipments/{id}/ship                       出库（限 mesCan('shipment')）
```

---

## 8. 离线与错误处理

App 是给天天在车间、仓库、客户现场跑的人用的，**信号不好是常态**：

- 列表类 GET 一律走 `cachedGet`，断网时回落缓存并在顶部显示 `OfflineNotice` +「数据更新于 X」
- **写操作（审批/接单/报工/出库）不做离线队列**——这些是有副作用的动作，
  断网时直接禁用按钮并提示「网络不可用，请连上网后再操作」。**绝不能本地假装成功。**
- 所有 422/403 的 `{ error }` 文案原样弹出，不要改写、不要吞掉换成「操作失败」
- 写操作成功后就地更新那一行，不整页重载

---

## 9. 验收清单

- [ ] 没有 `mes` 模块权限的账号，工作台看不到 MES 卡，手打 `/mes` 也进不去
- [ ] `/erp` 还是占位页，没被动过
- [ ] 待办三段的数字与列表条数一致，批完一单数字立刻减一
- [ ] 驳回/退回/出库驳回三处都强制填原因，不填不让提交
- [ ] 超时未接单的行排在最前且标红
- [ ] 纯业务员账号进订单详情，**看不到任何采购单、供应商、成本、金额**
- [ ] 报工能在 15 秒内单手完成一次（选单 → 填数 → 提交）
- [ ] 库存页成品行「结存 / 预占 / 可用」三个数都在
- [ ] 飞行模式下打开各列表有缓存内容 + 离线提示，写操作按钮禁用
- [ ] 深色模式每一页都过一遍，`env(safe-area-inset-*)` 都处理了
- [ ] 390pt 宽下没有横向滚动（材料明细表格除外，那个自己带横滚容器）

---

## 10. 不要做的事

- 不要做 BOM 编辑、采购单建单、采购申请、质检录入、序列号、主数据（物料/供应商/仓库）、产品档案增删改
- 不要做生产订单的新建和编辑
- 不要碰 ERP
- 不要引图表库（首页那几条分布用 div 画）
- 不要改 `src/api/client.js` 的鉴权和缓存逻辑
- 不要自己造视觉，`UI_BRIEF.md` 里已经定稿了
