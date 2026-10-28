# agent 取数的权限收口。
#
# agent 跑在后台任务里，拿不到控制器那套 Current/helper，所以这里按同一套口径重算一遍。
# ⚠️ 口径必须和 Api::V1::Accounts::Crm::BaseController 的 visible_customers /
# scope_by_mail_owner / scope_by_team_owner 保持一致——两边一走偏，就等于开了一个
# 「用 AI 能看到别人客户和别人邮件」的后门。
class Crm::Agent::Scope
  def initialize(account:, account_user:)
    @account = account
    @account_user = account_user
    @access = Crm::AccessScope.new(account, account_user)
  end

  attr_reader :account

  def user_id = @account_user&.user_id

  # 写入类工具要把真人挂到 audited 的操作历史上。agent 跑在后台任务里没有 Current.user，
  # 不挂就是一条「谁建的不知道」的记录（客户档案的操作历史是查错时唯一的线索）。
  def user = @user ||= User.find_by(id: user_id)

  # 一轮里最多让它查几次。防的是模型钻进死循环（反复查同一个客户）把钱和时间烧光。
  # 16 是按最长的真实链路给的：找客户 → 看档案 → 翻邮件 → 查历史价 → 查库存 → 建草稿，
  # 中间还会补查几次产品，12 次曾不够用。
  MAX_TOOL_CALLS = 16

  def tool_calls = @tool_calls ||= 0

  # 超了不再执行工具，但也**不中断这一轮**：工具改为回一句「别查了，用已有信息作答」，
  # 模型收到后会拿前面十几次查到的东西收口。原来是直接抛异常——前面查的全白费，
  # 用户只拿到一句「请把问题拆小一点再问」，钱花了、答案没有。
  def take_tool_budget!
    @tool_calls = tool_calls + 1
    @tool_calls <= MAX_TOOL_CALLS
  end

  def budget_exhausted? = tool_calls > MAX_TOOL_CALLS

  # 这一轮真做出来的东西（邮件草稿、PI 草稿）。
  # 工具只能回一段文本给模型，模型再转述成「去草稿箱看一下」——用户还得自己翻。
  # 这里另记一份，跑完挂到回答上，前端摆成能点的入口（见 Runner#assistant_meta）。
  def artifacts = @artifacts ||= []

  # 同一轮里同一个东西只挂一个入口：一轮下来可能查同一个客户三次（档案、邮件、订单进度），
  # 摆三颗一模一样的按钮像是建了三份东西。
  def record_artifact(kind:, id:, label:, customer_id:)
    return if artifacts.any? { |a| a[:kind] == kind && a[:id] == id }

    artifacts << { kind: kind, id: id, label: label, customer_id: customer_id }
  end

  # 可见私海（团队口径归属 + 被共享）∪ 公海
  def customers
    ids = @access.team_visible_owner_ids
    return @account.crm_customers if ids == :all

    @account.crm_customers.where(
      'crm_customers.account_owner_id IN (:ids) OR :uid = ANY(crm_customers.shared_user_ids) ' \
      'OR crm_customers.is_in_public_pool',
      ids: ids, uid: user_id
    )
  end

  # 邮件是私人往来：老板看全员，CRM 团队负责人看本团队，其余只看自己。
  def emails
    ids = @access.mail_visible_owner_ids
    ids == :all ? @account.crm_emails : @account.crm_emails.where(owner_id: ids)
  end

  def sales_orders
    ids = @access.team_visible_owner_ids
    ids == :all ? @account.crm_sales_orders : @account.crm_sales_orders.where(owner_id: ids)
  end

  def pis
    ids = @access.team_visible_owner_ids
    ids == :all ? @account.crm_pis : @account.crm_pis.where(owner_id: ids)
  end

  def opportunities
    ids = @access.team_visible_owner_ids
    ids == :all ? @account.crm_opportunities : @account.crm_opportunities.where(owner_id: ids)
  end

  # 跟进任务的负责人列是 assignee_id（与跟进任务列表控制器同口径）。
  def follow_up_tasks
    ids = @access.team_visible_owner_ids
    ids == :all ? @account.crm_follow_up_tasks : @account.crm_follow_up_tasks.where(assignee_id: ids)
  end

  # 应收自己那个 owner_id 可能是空的（财务手工建的单），所以跟着**客户**的可见范围走，
  # 不按 owner_id——否则业务员问「谁还欠钱」会漏掉一批本该他管的客户。
  def receivables
    ids = @access.team_visible_owner_ids
    ids == :all ? @account.erp_receivables : @account.erp_receivables.where(crm_customer_id: customers.select(:id))
  end

  # 跟进记录：和客户同一个团队口径（按录入人 owner_id）。
  def follow_up_notes
    ids = @access.team_visible_owner_ids
    ids == :all ? @account.crm_follow_up_notes : @account.crm_follow_up_notes.where(owner_id: ids)
  end

  def quotes
    ids = @access.team_visible_owner_ids
    ids == :all ? @account.crm_quotes : @account.crm_quotes.where(owner_id: ids)
  end

  # 定制询价申请：自己提的（applicant）＋ 指给自己报价的（pricer）。
  # 带上 pricer 这一半，主管问「有几张等我报价」才答得出来。
  def quote_requests
    ids = @access.team_visible_owner_ids
    return @account.crm_quote_requests if ids == :all

    @account.crm_quote_requests.where('applicant_id IN (:ids) OR pricer_id = :uid', ids: ids, uid: user_id)
  end

  # 出货单跟着**客户**的可见范围走，不按 owner_id：出货单的 owner 常是仓管或 MES 那边的人，
  # 按 owner 过滤业务员一张都看不到自己客户的出货。
  def shipments
    ids = @access.team_visible_owner_ids
    ids == :all ? @account.mes_shipments : @account.mes_shipments.where(crm_customer_id: customers.select(:id))
  end

  def sales_targets
    ids = @access.team_visible_owner_ids
    ids == :all ? @account.crm_sales_targets : @account.crm_sales_targets.where(owner_id: ids)
  end

  # 提成表、考核表只给**本人**：这是薪酬数据，比业务数据敏感一档。
  # 团队负责人要看下属的，去提成表/考核页按原有权限看，不从 AI 这边开口子
  # （那两个页面本来就有自己的审批链路和可见规则，这里跟着放宽等于绕过它们）。
  def my_commission_sheets = @account.crm_commission_sheets.where(owner_id: user_id)

  def my_kpi_sheets = @account.crm_kpi_sheets.where(owner_id: user_id)

  # 价格表：已发布的全员可见——它本来就是发给客户的报价依据。
  # 草稿和归档版不给：草稿是还没定的价，归档版是已经被顶掉的旧价，拿去报价就是事故。
  def published_price_lists = @account.crm_price_lists.published

  # 知识库口径照 Api::V1::Accounts::Crm::KnowledgeDocsController 来——那边是人点进去看的同一批文档，
  # 两边一走偏，AI 要么漏掉他本来看得见的资料，要么把不该给的板块读出来：
  # · 销售库（SALES）的公司文档 CRM 侧全员可读，不卡板块；
  # · 文档中心（GENERAL）的公司文档卡板块可见性（没挂板块的旧文档全员可见，
  #   管理员/副管理员和板块负责人不受限）；
  # · 个人文档只有本人。
  # WhatsApp 会话：只给这个人自己是成员的收件箱。
  #
  # 个人号是一人一个收件箱（生产里「张欢 的 WhatsApp」「罗家明 的 WhatsApp 1」各 1 个成员），
  # 所以按 inbox_members 收口就等于「只看自己的号」，和他在会话界面看到的完全一致。
  # 管理员走 all_access? 放行全部——和邮件那边「只有老板看全员」同一个口径。
  def whatsapp_conversations
    scope = @account.conversations.joins(:inbox).where(inboxes: { channel_type: %w[Channel::Whatsapp Channel::WhatsappWeb] })
    return scope if @access.all_access?

    scope.where(inbox_id: Inbox.joins(:inbox_members).where(inbox_members: { user_id: user_id }).select(:id))
  end

  def knowledge_docs
    @account.crm_knowledge_docs.kept.where(
      KNOWLEDGE_SQL, company: 'COMPANY', personal: 'PERSONAL', sales: 'SALES',
                     unrestricted: @access.all_access?, sids: visible_doc_section_ids, uid: user_id
    )
  end

  KNOWLEDGE_SQL = <<~SQL.squish
    (crm_knowledge_docs.scope = :company AND crm_knowledge_docs.library = :sales)
    OR (crm_knowledge_docs.scope = :company
        AND (:unrestricted OR section_id IS NULL OR section_id IN (:sids)))
    OR (crm_knowledge_docs.scope = :personal AND owner_id = :uid)
  SQL

  # 可见板块 ∪ 自己负责的板块（负责人能编辑自己板块的文档，自然也看得见）。
  def visible_doc_section_ids
    @visible_doc_section_ids ||=
      (Crm::DocSection.visible_ids_for(@account, user_id) + Crm::DocSection.managed_ids_for(@account, user_id)).uniq
  end
end
