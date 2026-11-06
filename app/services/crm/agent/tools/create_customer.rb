# 从询盘建客户档案——**先查重，撞了就不建**。
#
# 典型场景：陌生询盘进来，company_lookup 背调完说这家靠谱，接着就该建档。
# 以前到这一步 agent 就没辙了，业务员得自己回客户页把邮箱公司名再敲一遍。
#
# 查重是硬门槛，不是提醒：AI 建重复档案的代价比不建高得多——
# 两个业务员各跟一半、往来邮件分散在两个档案下，事后合并要人工对。
# 口径照 Api::V1::Accounts::Crm::CustomersController 的建档查重（邮箱/电话/WhatsApp/公司名），
# **跨负责人全库查**（撞单检测不按辖区收口，否则两个人各建一份谁都看不见对方那份）。
class Crm::Agent::Tools::CreateCustomer < Crm::Agent::Tools::Base
  writes_data

  description '新建客户档案（处理陌生询盘时用）。会先按邮箱、电话、公司名全库查重，撞到已有客户就不建、把那条报给你。建完归属人是你自己。'
  param :name, desc: '公司名（必填）'
  param :contact_email, desc: '联系邮箱', required: false
  param :contact_name, desc: '联系人姓名', required: false
  param :contact_phone, desc: '联系电话', required: false
  param :whats_app, desc: 'WhatsApp 号', required: false
  param :website, desc: '公司网站', required: false
  param :country, desc: '国家，写英文大写下划线式如 GERMANY、SAUDI_ARABIA、UAE；不确定就别传', required: false
  param :source, desc: '来源：ALIBABA｜WEBSITE｜EXHIBITION｜REFERRAL｜EMAIL｜WHATSAPP｜OTHER', required: false
  param :remark, desc: '备注：询盘里提到的需求、数量、目标价等', required: false

  # 只有公司名是必填（显式写出来让 RubyLLM 校验），其余八个可选项塞 opts：
  # 全列出来会撞 rubocop 的参数个数上限。
  def execute(name:, **opts)
    company = name.to_s.strip
    return '公司名不能为空。' if company.blank?

    hit = duplicate(company, opts[:contact_email], opts[:contact_phone], opts[:whats_app])
    return dup_text(hit) if hit

    customer = create(company, opts)
    scope.record_artifact(kind: 'customer', id: customer.id, customer_id: customer.id,
                          label: "客户档案：#{company.truncate(20)}")
    "已建客户档案「#{customer.name}」（ID #{customer.id}，归属你自己，状态=潜在客户）。" \
      '建议顺手补上国家、行业和需求备注——档案完整度会影响公海回收和考核。'
  end

  private

  # 全库查（不经 scope.customers）：撞单检测必须跨负责人，否则等于没查。
  # 只把名字、编码、负责人、状态报出去——别人私海客户的联系方式不能借 AI 看到。
  def duplicate(company, email, phone, whatsapp)
    all = scope.account.crm_customers
    by_email(all, email) || by_phone(all, phone) || by_phone(all, whatsapp) || by_name(all, company)
  end

  def by_email(all, value)
    email = value.to_s.strip.downcase
    return nil if email.length < 5

    row = all.where('LOWER(contact_email) = ?', email).first
    row && [row, "邮箱 #{email}"]
  end

  # 比后 9 位，让 +971501234567 / 0501234567 判为同号（同建档页口径）。短号不查，太容易误撞。
  def by_phone(all, value)
    digits = value.to_s.gsub(/\D/, '')
    return nil if digits.length < 8

    tail = digits.last(9)
    row = all.where("REGEXP_REPLACE(COALESCE(contact_phone, ''), '\\D', '', 'g') LIKE :t " \
                    "OR REGEXP_REPLACE(COALESCE(whats_app, ''), '\\D', '', 'g') LIKE :t", t: "%#{tail}").first
    row && [row, "电话/WhatsApp 尾号 #{tail}"]
  end

  def by_name(all, company)
    return nil if company.length < 2

    row = all.where('LOWER(TRIM(name)) = ?', company.downcase).first
    row && [row, "公司名「#{company}」"]
  end

  STATUS_LABELS = { 'PROSPECT' => '潜在客户', 'FOLLOWING' => '跟进中', 'WON' => '已成交',
                    'DORMANT' => '沉睡', 'LOST' => '已流失' }.freeze

  def dup_text((row, reason))
    "没建——#{reason} 和系统里已有的客户撞了：#{row.name}（ID #{row.id}，编码 #{row.customer_code.presence || '—'}，" \
      "#{owner_label(row)}，状态 #{STATUS_LABELS[row.customer_status] || '未填'}）。" \
      '要么在那条上继续跟，要么先确认是不是同一家；确实是两家不同公司再手工建档。'
  end

  def owner_label(customer)
    return '在公海' if customer.is_in_public_pool
    return "归属 #{customer.account_owner.crm_display_name}" if customer.account_owner_id

    '未分配'
  end

  def create(company, attrs)
    Audited.audit_class.as_user(scope.user) do
      scope.account.crm_customers.create!(base_attrs(company).merge(contact_attrs(attrs)))
    end
  end

  def base_attrs(company)
    { name: company, account_owner_id: scope.user_id, customer_status: 'PROSPECT' }
  end

  # 文本字段「传了什么存什么」，一个映射表带过，省掉八行一样的 strip.presence。
  TEXT_FIELDS = { contact_email: :contact_email, contact_name: :primary_contact_name,
                  contact_phone: :contact_phone, whats_app: :whats_app, website: :website }.freeze

  def contact_attrs(attrs)
    text = TEXT_FIELDS.to_h { |key, column| [column, attrs[key].to_s.strip.presence] }
    text.merge(
      trade_country: enum_or_nil(attrs[:country], Crm::Customer::COUNTRIES, COUNTRY_DICT),
      source_channel: enum_or_nil(attrs[:source], Crm::Customer::SOURCE_CHANNELS, SOURCE_DICT),
      customer_remark: attrs[:remark].to_s.presence
    )
  end

  # 中英文归一复用导入服务那本字典：模型十次有八次传「德国」「阿里巴巴」而不是 GERMANY、ALIBABA，
  # 自己再写一份字典必然和导入那边走偏（那边也是同一批枚举）。
  COUNTRY_DICT = Crm::CustomerImportService::COUNTRY_MAP
  SOURCE_DICT = Crm::CustomerImportService::SOURCE_MAP

  # 字典也认不出来就留空（不像导入那边归 OTHER）：国家、来源都不是必填，
  # 而一个假的「其他」会把客户分布图和来源统计带偏，空着反倒提醒人去补。
  def enum_or_nil(value, allowed, dict)
    key = value.to_s.strip
    upper = key.upcase.tr(' -', '__')
    return upper if allowed.include?(upper)

    dict[key] || dict[key.downcase]
  end
end
