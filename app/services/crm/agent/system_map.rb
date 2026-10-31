# 喂给 agent 的「系统自己长什么样」。
#
# 为什么是预置文本、不是一个查询工具：问「邮件有没有拉黑功能」的人要的是一句话，
# 不是一次检索。给工具，它得先判断要不要查；预置进去，它开口就知道。
# 这份东西也小——全文两千来字，不值得为它多跑一轮。
#
# ⚠️ 这里只写**真实存在**的东西。地图错一条比没有地图更糟：
# 用户照着跑一趟空，下次就不信了（prompt.rb 里原来那条「别凭名字猜」就是这个意思，
# 现在不是不许它答，是给了它真东西才许答）。
#
# 维护：左侧栏加/改菜单项，这里跟着改；spec/services/crm/agent/system_map_spec.rb
# 会拿 Sidebar.vue 的真实菜单对一遍，漏了会红。
module Crm::Agent::SystemMap
  # 板块 → 菜单项。顺序和左侧栏一致，用户照着从上往下找得到。
  NAV = {
    '工作台' => '首页。今天要做的事（日程、待我审的单、待我填的考核表、MES 待办）都浮在这。',
    'AI 助手' => '就是你所在的这个页面。',
    '数据看板' => '外贸销售部数据看板 · 团队数据看板 · 个人数据看板 · 我的目标',
    '客户消息' => '全部消息 · 客户来源。WhatsApp、网页在线咨询这类即时消息走这里，' \
              '和「邮件中心」是两回事。',
    '邮件中心' => '收发邮件 · 邮件模板 · 邮箱账户',
    '客户' => '客户建档 · 私海客户 · 公海客户 · 流失预警 · 客户查重 · AI 背调',
    '销售流程' => '商机看板 · 标准价目表 · 定制报价 · 报价单管理 · PI 管理 · 销售订单 · ' \
              '历史 PI 补录 · 未关联客户的订单',
    '生产管理' => '生产看板 · 流水看板 · 站内通知 · 销售订单 · 生产任务单 · 产品档案 · ' \
              '采购申请单 · 采购单 · 供应商 · 物料单价表 · 仓库档案 · ' \
              '原料入库 · 库存 · 原料成品转换 · 采购退料 · ' \
              '生产领料 · 生产退料 · 生产报工 · 质量检验 · 成品入库 · 销售出库 · SN 追溯',
    '财务管理' => '财务看板 · 会计科目表 · 记账凭证 · 账簿 · 财务报表 · 应收台账 · 出库审核 · ' \
              '应付台账 · 资金账户 · 成本毛利 · BOM 成本表 · 费用报销 · 固定资产 · ' \
              '期末结账 · 财务通知 · 财务设置',
    'TikTok 经营' => '今日速览 · 数据看板 · 每日录入 · 出库利润表 · 支出台账 · 固定资产 · ' \
                   '店铺设置 · 部门管理',
    '销售资料 / 文档中心' => '公司资料 · 我的资料 · 全公司文档 · 回收站',
    '组织架构' => '部门与成员 · 组织架构图 · CRM 团队 · 成员权限 · 成员邀请',
    'HR·绩效考核' => '考核方案 · 考核表 · 提成表 · 绩效设置 · 员工档案 · 员工薪资配置',
    '考勤' => '上下班打卡、考勤记录、导出考勤 Excel。',
    '协同办公' => '我的审批 · 备用金台账 · 审批模板',
    '团队沟通' => '消息。公司内部同事之间聊天，不是跟客户的。',
    '日程' => '日程 Schedule。',
    '设置' => '客户设置 · 公海设置 · 定制报价模板 · AI 配置 · 业务分配'
  }.freeze

  # 不在菜单上、藏在某个页面里的操作。
  # 问「有没有 XX 功能」答错，十次有八次错在这类——它不是一个菜单项，
  # 是某张列表上的一个按钮，照菜单名根本找不着。
  INLINE = [
    '拉黑发件人 —— 邮件中心 → 收发邮件，打开那封信就能拉黑；拉黑是在**收进来之前丢弃**，' \
    '比「标记垃圾邮件」彻底。业务员拉黑只对自己生效，管理员/副管的落成全公司规则。' \
    '已拉黑的名单在 邮件中心 → 邮箱账户 里管理。',
    '邮件批量打标签、分发给同事 —— 收发邮件页勾选若干封之后。',
    '客户合并 —— 客户 → 客户查重，勾出重复的那几条，合并到选中的「保留」项（邮件、订单会跟着并过去）。',
    '客户批量改分组 / 改状态 —— 私海客户列表勾选之后。',
    '客户共享 / 分发给同事 —— 客户详情里。共享到的人可以在这个客户上建 PI、报价、销售订单、生产订单。',
    '采购单的收货日期 / 入库状态 / 入库时间 —— 生产管理 → 采购 → 采购单，列表上这三列。' \
    '收货日期是**采购员**在采购单建档页逐行填的「实际到料」；入库状态显示「已入库」或「未入库」，' \
    '连同入库时间都是**仓管**在原料入库单过账之后自动同步过来的，采购员改不了。' \
    '列多的时候可能要往右拉，也可以用右上角「列」把不看的列收起来。',
    '报价单转销售订单 —— 销售流程 → 报价单管理，报价单「已确认」之后。',
    'PI 付款转订单 —— 销售流程 → PI 管理，登记付款之后自动生成销售订单。',
    '导出 Excel / PDF —— PI、报价单、以及财务管理和生产管理下各列表页，都在页面右上角。' \
    '原料入库与退货那页导的是**当前筛选下的全量**，按单看导单据级、按明细看导料级（供应商/物料编码/规格/单价/金额）。',
    '银行日记账导入 Excel —— 财务管理 → 资金账户，右上角「导入日记账」。认金蝶出纳导出的那套列头；' \
    '账户按名称匹配资金账户，对不上的整行退回并点名；重复导同一个文件不会翻倍。只落流水，不生成凭证。',
    '制造费用按月分摊 —— 财务管理 → BOM 成本表，右上角「制造费用分摊」。' \
    '当月 5101 已过账发生额 ÷ 当月完工入库量，按各单入库量摊回销售订单。先预览再落账；' \
    '当月没有已过账的 5101 凭证就摊不出来，按钮是灰的。',
    '物料单价「从采购单回填」 —— 生产管理 → 采购 → 物料单价表，右上角。' \
    '每颗料取最近一次审批通过的采购价；只填空缺，不覆盖已维护的标准价。',
    '采购退料按来源单推料 —— 生产管理 → 仓库 → 采购退料，新建时选「来源单据」（原料入库单或车间退料单），' \
    '那张单收的料会自动推出来，勾要退的几行即可，不用手敲编码。可退量＝这张单收了多少 − 已经退掉多少。',
    '生产退料按任务单推料 —— 生产车间 → 生产退料，新建时选生产任务单，已领的料会推出来勾选。',
    '出库审核看收款 —— 财务管理 → 出库审核，每张单上直接列出收过哪几笔（日期/途径/收款账户/水单号/金额），' \
    '以及结算方式、收款账户、信保订单号。不用再回订单里翻。',
    '质检记录改 / 删 —— 生产车间 → 质量检验，列表行上。只有**本人录的**才能改删（管理员可兜底）。',
    '生产领料改 / 过账 —— 生产车间 → 生产领料，草稿行上有「编辑」「过账」。' \
    '能不能动看这张单是不是你能管的，不是看岗位。',
    '凭证批量删除 —— 财务管理 → 记账凭证，勾选若干张之后（只能删未过账的）。',
    '记账凭证的币种与辅助核算 —— 新建凭证时每一行都能选币种/汇率，也都能挂客户、供应商、订单、业务员、部门，' \
    '不要求科目先配好维度。',
    'ERP 多页签 —— 财务管理下各页会留在顶部页签里，切走再切回来，填到一半的凭证还在。',
    'AI 助手历史对话 —— 右下角 AI 球打开后，标题栏那个时钟图标；独立页在左侧「历史对话」里，点标题就能打开那一轮。',
    '撤回已提交的审批 / 考核表 —— 协同办公 → 我的审批、HR·绩效考核 → 考核表。'
  ].freeze

  # 同名不同物，答错方向比答不出更糟。
  PITFALLS = [
    '「销售订单」有两个，别指错：销售流程 → 销售订单 是业务员开给客户的那张；' \
    '生产管理 → 销售订单 是车间那张生产单（系统后台叫生产订单）。' \
    '问交期、排产、领料的，去生产管理那张；问金额、收款、提成的，去销售流程那张。',
    '「固定资产」有两处：财务管理下是公司账上的，TikTok 经营下是那条业务线自己的。',
    '「数据看板」是 CRM 销售数据；生产看板、财务看板各在自己板块下。'
  ].freeze

  # 路由名 → 这个页面在界面上叫什么。给「用户现在正看着哪一页」用。
  #
  # 从 Sidebar.vue 真实抽出来的，不是手敲的；spec 会拿侧栏再对一遍。
  # 用处：用户站在某张单前面问「这单卡哪了」，不该再被反问「哪张单」——
  # 他看得见的东西，助手也该看得见（2026-10-27：问「回一下邮件 #124」
  # 它反问「这是哪个客户」，根子就是它看不见用户在看什么）。
  ROUTE_LABEL = {
    'crm_agent_index' => 'AI 助手',
    'crm_ai_background_check_index' => 'AI 背调',
    'crm_ai_settings_index' => 'AI 配置',
    'crm_approval_templates_index' => '审批模板',
    'crm_approvals_index' => '我的审批',
    'crm_attendance_index' => '考勤',
    'crm_business_cards_index' => '名片夹',
    'crm_commission_sheets_index' => '提成表',
    'crm_commission_sheet_detail' => '提成表明细',
    'crm_customers_index' => '客户列表',
    'crm_customer_detail_index' => '客户详情',
    'crm_customer_dupes_index' => '客户查重',
    'crm_customer_intake_index' => '客户建档',
    'crm_customer_settings_index' => '客户设置',
    'crm_dashboard_index' => '外贸销售部数据看板',
    'crm_doc_center_index' => '文档中心',
    'crm_knowledge_docs_index' => '销售知识库',
    'crm_opportunities_index' => '商机看板',
    'crm_sales_targets_index' => '我的目标',
    'crm_sales_orders_index' => '销售订单',
    'crm_email_templates_index' => '邮件模板',
    'crm_emails_index' => '收发邮件',
    'crm_employee_comps_index' => '员工薪资配置',
    'crm_employees_index' => '员工档案',
    'crm_funnel_index' => '商机看板',
    'crm_inbox_collaborators_index' => '业务分配',
    'crm_kpi_schemes_index' => '考核方案',
    'crm_kpi_scheme_editor' => '考核方案编辑',
    'crm_kpi_sheets_index' => '考核表',
    'crm_kpi_sheet_detail' => '考核表明细',
    'crm_mail_accounts_index' => '邮箱账户',
    'crm_member_invites_index' => '成员邀请',
    'crm_members_index' => '成员权限',
    'crm_my_target_index' => '我的目标',
    'crm_org_chart_index' => '组织架构图',
    'crm_org_structure_index' => '部门与成员',
    'crm_performance_settings_index' => '绩效设置',
    'crm_petty_cash_index' => '备用金台账',
    'crm_pi_backfill_index' => '历史 PI 补录',
    'crm_pis_index' => 'PI 管理',
    'crm_price_lists_index' => '标准价目表',
    'crm_public_pool_settings_index' => '公海设置',
    'crm_quote_request_templates_index' => '定制报价模板',
    'crm_quote_requests_index' => '定制报价',
    'crm_quotes_index' => '报价单管理',
    'crm_schedule_index' => '日程 Schedule',
    'crm_team_chat_index' => '消息',
    'crm_team_dashboard_index' => '团队数据看板',
    'crm_teams_index' => 'CRM 团队',
    'crm_workspace_index' => '工作台',
    'erp_accounts_index' => '会计科目表',
    'erp_bom_costs_index' => 'BOM 成本表',
    'erp_cash_index' => '资金账户',
    'erp_dashboard_index' => '财务看板',
    'erp_expenses_index' => '费用报销',
    'erp_fixed_assets_index' => '固定资产',
    'erp_ledgers_index' => '账簿',
    'erp_margin_index' => '成本毛利',
    'erp_notifications_index' => '财务通知',
    'erp_payables_index' => '应付台账',
    'erp_periods_index' => '期末结账',
    'erp_receivables_index' => '应收台账',
    'erp_reports_index' => '财务报表',
    'erp_settings_index' => '财务设置',
    'erp_shipment_approvals_index' => '出库审核',
    'erp_vouchers_index' => '记账凭证',
    'home' => '全部消息',
    'mes_bom_intake_index' => '生产任务单建档',
    'mes_boms_index' => '生产任务单',
    'mes_dashboard_index' => '生产看板',
    'mes_fg_inbound_index' => '成品入库',
    'mes_inspections_index' => '质量检验',
    'mes_material_issues_index' => '生产领料',
    'mes_material_returns_index' => '生产退料',
    'mes_material_prices_index' => '物料单价表',
    'mes_notifications_index' => '站内通知',
    'mes_pipeline_index' => '流水看板',
    'mes_production_orders_index' => '销售订单',
    'mes_production_order_intake_index' => '销售订单建档',
    'mes_production_records_index' => '生产报工',
    'mes_products_index' => '产品档案',
    'mes_purchase_orders_index' => '采购单',
    'mes_purchase_order_intake_index' => '采购单建档',
    'mes_purchase_requisitions_index' => '采购申请单',
    'mes_serial_numbers_index' => 'SN 追溯',
    'mes_shipments_index' => '销售出库',
    'mes_stock_balances_index' => '库存',
    'mes_stock_conversions_index' => '原料成品转换',
    'mes_stock_entries_index' => '原料入库',
    'mes_supplier_returns_index' => '采购退料',
    'mes_suppliers_index' => '供应商',
    'mes_warehouses_index' => '仓库档案',
    'tiktok_assets_index' => '固定资产',
    'tiktok_dashboard_index' => '数据看板',
    'tiktok_departments_index' => '部门管理',
    'tiktok_expenses_index' => '支出台账',
    'tiktok_profit_index' => '出库利润表',
    'tiktok_sales_records_index' => '每日录入',
    'tiktok_shop_settings_index' => '店铺设置',
    'tiktok_today_index' => '今日速览'
  }.freeze

  def self.text
    <<~MAP
      ── 系统功能地图 ──
      下面是 wintouchspace 左侧栏的真实结构。用户问「XX 功能在哪」「有没有 XX」，照这份答。

      #{NAV.map { |section, items| "【#{section}】#{items}" }.join("\n")}

      藏在页面里、不在菜单上的操作：
      #{INLINE.map { |line| "· #{line}" }.join("\n")}

      容易指错的地方：
      #{PITFALLS.map { |line| "· #{line}" }.join("\n")}

      用这份地图的规矩：
      1. 地图里有 → 直接说位置，说到菜单那一级（「邮件中心 → 邮箱账户」），别再反问他想干嘛。
      2. 地图里没有 → **第一句先明说「系统里没有这个功能」**，再问一句要不要帮他报给管理员。
         不要开口就甩工单号：他问的是「有没有」，收到的却是「已报给管理员 #21」，
         等于没回答问题（2026-10-27 实测原样如此）。也别猜「一般在设置里」
         「可能在财务模块下」——猜错一次他白跑一趟，下次就不问你了。
         只有他明确表达诉求（「这是 bug」「帮我报一下」「为什么没有这个」）才直接
         report_issue 不再问；纯打听「有没有 X」每次都开单，管理员那头会被淹掉。
      3. 每个人能看到哪些板块是权限决定的，地图上有不等于他账号里有。照实说位置就行，
         不用替他判断权限；他要是说「我这儿没有这个菜单」，那是权限没开，让他找管理员，
         别改口说这功能不存在。
      4. 这份地图只到菜单一级。具体某一步怎么点、填什么，看右上角头像菜单里的
         《系统用户使用指南》和《上岗 SOP》；那里面没有的，照第 2 条报上去。
    MAP
  end
end
