# 客户批量导入：吃前端映射好的行数据（键名 = CRM 字段），做三件事——
#   1. 中文自由文本 → 枚举码归一化（国家/地区/来源/等级/行业/状态/币种/联系偏好）；
#   2. 按公司名（账号内不区分大小写）查重，命中即跳过并回报归属；
#   3. 建 Crm::Customer + 同步主联系人字段，并建 Contact（crm_customer_id 关联）。
# 逐行独立事务，单行失败不影响整体；返回逐行结果供前端汇总。
#
# 从小满等外部 CRM 导出的列头/取值千变万化，命中不了的枚举值：
#   - 该枚举含 OTHER 的落 OTHER，否则置空；两种都在该行 warnings 里标出原始值，让人工复核。
class Crm::CustomerImportService
  # 归一化字典：小满/外贸常见中文写法 → 模型枚举码。键统一 downcase+去空格后匹配，
  # 已经是英文码（USA/ALIBABA…）的原样命中。
  COUNTRY_MAP = {
    '美国' => 'USA', '德国' => 'GERMANY', '英国' => 'UK', '法国' => 'FRANCE', '意大利' => 'ITALY',
    '西班牙' => 'SPAIN', '加拿大' => 'CANADA', '澳大利亚' => 'AUSTRALIA', '澳洲' => 'AUSTRALIA',
    '日本' => 'JAPAN', '韩国' => 'SOUTH_KOREA', '印度' => 'INDIA', '俄罗斯' => 'RUSSIA',
    '巴西' => 'BRAZIL', '墨西哥' => 'MEXICO', '荷兰' => 'NETHERLANDS', '比利时' => 'BELGIUM',
    '瑞士' => 'SWITZERLAND', '瑞典' => 'SWEDEN', '挪威' => 'NORWAY', '丹麦' => 'DENMARK',
    '芬兰' => 'FINLAND', '奥地利' => 'AUSTRIA', '波兰' => 'POLAND', '捷克' => 'CZECH',
    '土耳其' => 'TURKEY', '阿联酋' => 'UAE', '沙特' => 'SAUDI_ARABIA', '沙特阿拉伯' => 'SAUDI_ARABIA',
    '新加坡' => 'SINGAPORE', '马来西亚' => 'MALAYSIA', '泰国' => 'THAILAND', '越南' => 'VIETNAM',
    '印尼' => 'INDONESIA', '印度尼西亚' => 'INDONESIA', '菲律宾' => 'PHILIPPINES',
    '南非' => 'SOUTH_AFRICA', '阿根廷' => 'ARGENTINA', '智利' => 'CHILE', '哥伦比亚' => 'COLOMBIA',
    '秘鲁' => 'PERU', '以色列' => 'ISRAEL', '埃及' => 'EGYPT', '尼日利亚' => 'NIGERIA',
    '肯尼亚' => 'KENYA', '希腊' => 'GREECE', '葡萄牙' => 'PORTUGAL', '爱尔兰' => 'IRELAND',
    '新西兰' => 'NEW_ZEALAND', '台湾' => 'TAIWAN', '香港' => 'HONG_KONG', '巴基斯坦' => 'PAKISTAN',
    '孟加拉' => 'BANGLADESH', '孟加拉国' => 'BANGLADESH', '乌克兰' => 'UKRAINE', '罗马尼亚' => 'ROMANIA',
    '匈牙利' => 'HUNGARY', '保加利亚' => 'BULGARIA', '克罗地亚' => 'CROATIA', '摩洛哥' => 'MOROCCO',
    '伊朗' => 'IRAN', '伊拉克' => 'IRAQ', '卡塔尔' => 'QATAR', '科威特' => 'KUWAIT', '阿曼' => 'OMAN',
    '缅甸' => 'MYANMAR', '柬埔寨' => 'CAMBODIA', '老挝' => 'LAOS', '哈萨克斯坦' => 'KAZAKHSTAN',
    '乌兹别克斯坦' => 'UZBEKISTAN',
    '加纳' => 'GHANA', '塞内加尔' => 'SENEGAL', '安哥拉' => 'ANGOLA',
    '赞比亚' => 'ZAMBIA', '埃塞俄比亚' => 'ETHIOPIA', '喀麦隆' => 'CAMEROON',
    '坦桑尼亚' => 'TANZANIA', '贝宁' => 'BENIN', '索马里' => 'SOMALIA',
    '多哥' => 'TOGO', '布基纳法索' => 'BURKINA_FASO', '利比亚' => 'LIBYA',
    '博茨瓦纳' => 'BOTSWANA', '津巴布韦' => 'ZIMBABWE', '南苏丹' => 'SOUTH_SUDAN',
    '马里' => 'MALI', '塞拉利昂' => 'SIERRA_LEONE', '几内亚' => 'GUINEA',
    '佛得角' => 'CAPE_VERDE', '中非' => 'CENTRAL_AFRICAN_REPUBLIC', '中非共和国' => 'CENTRAL_AFRICAN_REPUBLIC',
    '苏丹' => 'SUDAN', '莫桑比克' => 'MOZAMBIQUE', '马拉维' => 'MALAWI',
    '毛里求斯' => 'MAURITIUS', '阿尔及利亚' => 'ALGERIA', '突尼斯' => 'TUNISIA',
    '科特迪瓦' => 'IVORY_COAST', '象牙海岸' => 'IVORY_COAST', '乌干达' => 'UGANDA',
    '卢旺达' => 'RWANDA', '加蓬' => 'GABON', '刚果（布）' => 'CONGO',
    '刚果布' => 'CONGO', '刚果共和国' => 'CONGO', '刚果（金）' => 'DR_CONGO',
    '刚果金' => 'DR_CONGO', '民主刚果' => 'DR_CONGO', '马达加斯加' => 'MADAGASCAR',
    '纳米比亚' => 'NAMIBIA', '留尼汪' => 'REUNION', '委内瑞拉' => 'VENEZUELA',
    '哥斯达黎加' => 'COSTA_RICA', '危地马拉' => 'GUATEMALA', '海地' => 'HAITI',
    '洪都拉斯' => 'HONDURAS', '萨尔瓦多' => 'EL_SALVADOR', '玻利维亚' => 'BOLIVIA',
    '巴巴多斯' => 'BARBADOS', '巴哈马' => 'BAHAMAS', '厄瓜多尔' => 'ECUADOR',
    '乌拉圭' => 'URUGUAY', '巴拉圭' => 'PARAGUAY', '多米尼加' => 'DOMINICAN_REPUBLIC',
    '多米尼加共和国' => 'DOMINICAN_REPUBLIC', '巴拿马' => 'PANAMA', '牙买加' => 'JAMAICA',
    '特立尼达和多巴哥' => 'TRINIDAD_AND_TOBAGO', '古巴' => 'CUBA', '尼加拉瓜' => 'NICARAGUA',
    '黎巴嫩' => 'LEBANON', '约旦' => 'JORDAN', '巴林' => 'BAHRAIN',
    '也门' => 'YEMEN', '叙利亚' => 'SYRIA', '阿富汗' => 'AFGHANISTAN',
    '斯里兰卡' => 'SRI_LANKA', '尼泊尔' => 'NEPAL', '蒙古' => 'MONGOLIA',
    '文莱' => 'BRUNEI', '马尔代夫' => 'MALDIVES', '格鲁吉亚' => 'GEORGIA',
    '亚美尼亚' => 'ARMENIA', '阿塞拜疆' => 'AZERBAIJAN', '塞浦路斯' => 'CYPRUS',
    '马耳他' => 'MALTA', '卢森堡' => 'LUXEMBOURG', '冰岛' => 'ICELAND',
    '爱沙尼亚' => 'ESTONIA', '拉脱维亚' => 'LATVIA', '立陶宛' => 'LITHUANIA',
    '斯洛伐克' => 'SLOVAKIA', '斯洛文尼亚' => 'SLOVENIA', '塞尔维亚' => 'SERBIA',
    '波斯尼亚' => 'BOSNIA', '波黑' => 'BOSNIA', '阿尔巴尼亚' => 'ALBANIA',
    '北马其顿' => 'NORTH_MACEDONIA', '马其顿' => 'NORTH_MACEDONIA', '白俄罗斯' => 'BELARUS',
    '瓦努阿图' => 'VANUATU', '斐济' => 'FIJI', '巴布亚新几内亚' => 'PAPUA_NEW_GUINEA'
  }.freeze

  REGION_MAP = {
    '北美' => 'NORTH_AMERICA', '北美洲' => 'NORTH_AMERICA', '欧洲' => 'EUROPE', '南美' => 'SOUTH_AMERICA',
    '南美洲' => 'SOUTH_AMERICA', '中东' => 'MIDDLE_EAST', '东南亚' => 'SOUTHEAST_ASIA',
    '非洲' => 'AFRICA', '其他' => 'OTHER', '其它' => 'OTHER'
  }.freeze

  INDUSTRY_MAP = {
    '零售' => 'RETAIL', '零售商' => 'RETAIL', '批发' => 'WHOLESALE', '批发商' => 'WHOLESALE',
    '经销商' => 'DISTRIBUTOR', '分销' => 'DISTRIBUTOR', '分销商' => 'DISTRIBUTOR', '代理商' => 'DISTRIBUTOR',
    '制造' => 'MANUFACTURING', '制造商' => 'MANUFACTURING', '工厂' => 'MANUFACTURING', '生产商' => 'MANUFACTURING',
    '电商' => 'ECOMMERCE', '电子商务' => 'ECOMMERCE', '跨境电商' => 'ECOMMERCE', '其他' => 'OTHER', '其它' => 'OTHER'
  }.freeze

  SOURCE_MAP = {
    '阿里巴巴' => 'ALIBABA', '阿里' => 'ALIBABA', 'alibaba' => 'ALIBABA', '1688' => 'ALIBABA',
    '官网' => 'WEBSITE', '网站' => 'WEBSITE', '独立站' => 'WEBSITE', '谷歌' => 'WEBSITE', 'google' => 'WEBSITE',
    '展会' => 'EXHIBITION', '展览' => 'EXHIBITION', '广交会' => 'EXHIBITION',
    '转介绍' => 'REFERRAL', '介绍' => 'REFERRAL', '推荐' => 'REFERRAL', '老客户介绍' => 'REFERRAL',
    '邮件' => 'EMAIL', '开发信' => 'EMAIL', 'edm' => 'EMAIL', '其他' => 'OTHER', '其它' => 'OTHER'
  }.freeze

  STATUS_MAP = {
    '潜在' => 'PROSPECT', '潜在客户' => 'PROSPECT', '跟进' => 'FOLLOWING', '跟进中' => 'FOLLOWING',
    '成交' => 'WON', '已成交' => 'WON', '赢单' => 'WON', '沉睡' => 'DORMANT', '休眠' => 'DORMANT',
    '流失' => 'LOST', '丢单' => 'LOST', '战败' => 'LOST'
  }.freeze

  CURRENCY_MAP = {
    '美元' => 'USD', 'usd' => 'USD', '$' => 'USD', '人民币' => 'CNY', 'cny' => 'CNY', 'rmb' => 'CNY',
    '¥' => 'CNY', '欧元' => 'EUR', 'eur' => 'EUR', '€' => 'EUR'
  }.freeze

  CONTACT_PREF_MAP = {
    '邮件' => 'EMAIL', '邮箱' => 'EMAIL', 'email' => 'EMAIL', '电话' => 'PHONE', 'phone' => 'PHONE',
    'whatsapp' => 'WHATSAPP', '微信' => 'WECHAT', 'wechat' => 'WECHAT'
  }.freeze

  # 每个枚举字段 → [字典, 是否有 OTHER 兜底]
  ENUM_FIELDS = {
    trade_country: [COUNTRY_MAP, true],
    trade_region: [REGION_MAP, true],
    industry: [INDUSTRY_MAP, true],
    source_channel: [SOURCE_MAP, true],
    customer_status: [STATUS_MAP, false],
    currency_preference: [CURRENCY_MAP, false],
    contact_preference: [CONTACT_PREF_MAP, false]
  }.freeze

  # 直接透传的自由文本字段（不做枚举归一）
  TEXT_FIELDS = %i[
    name customer_code website address trade_city customer_remark customer_group product_group
    linkedin whats_app wechat
  ].freeze

  def initialize(account:, user:, rows:, default_owner_id: nil)
    @account = account
    @user = user
    @rows = Array(rows)
    # 统一负责人：非本账号成员或空 → 未分配（nil），避免建档时外键报错。
    owner_id = default_owner_id.presence
    @default_owner_id = owner_id if owner_id && @account.account_users.exists?(user_id: owner_id)
  end

  # => { created:, skipped:, failed:, results: [{ row:, name:, status:, message:, warnings: [] }] }
  def call
    results = @rows.each_with_index.map { |row, idx| process_row(row.to_h.symbolize_keys, idx) }
    {
      created: results.count { |r| r[:status] == 'created' },
      skipped: results.count { |r| r[:status] == 'skipped' },
      failed: results.count { |r| r[:status] == 'failed' },
      results: results
    }
  end

  private

  def process_row(row, idx)
    name = row[:name].to_s.strip
    return result(idx, name, 'failed', message: '公司名为空') if name.blank?

    existing = @account.crm_customers.where('LOWER(name) = ?', name.downcase).first
    return result(idx, name, 'skipped', message: "已存在（#{owner_label(existing)}）") if existing

    warnings = []
    attrs = build_customer_attrs(row, warnings)

    ActiveRecord::Base.transaction do
      customer = @account.crm_customers.create!(attrs)
      build_contact(customer, row, warnings)
      result(idx, name, 'created', warnings: warnings)
    end
  rescue ActiveRecord::RecordInvalid => e
    result(idx, name, 'failed', message: e.record.errors.full_messages.join('；'))
  rescue StandardError => e
    result(idx, name, 'failed', message: e.message)
  end

  # 主联系人字段冗余到客户表（记录页直接可见）：客户列 => 源行键
  PRIMARY_CONTACT_MIRROR = {
    primary_contact_name: :contact_name, contact_job_title: :contact_job_title,
    contact_email: :contact_email, contact_phone: :contact_phone
  }.freeze

  def build_customer_attrs(row, warnings)
    attrs = { account_owner_id: @default_owner_id }
    attrs.merge!(text_attrs(row))
    attrs.merge!(enum_attrs(row, warnings))
    attrs.merge!(mirror_attrs(row))
    attrs[:customer_level] = normalize_level(row[:customer_level], warnings) if row[:customer_level].present?
    attrs.compact
  end

  def text_attrs(row)
    TEXT_FIELDS.index_with { |f| row[f].to_s.strip.presence }.compact
  end

  def enum_attrs(row, warnings)
    ENUM_FIELDS.filter_map do |field, (dict, has_other)|
      raw = row[field].to_s.strip
      [field, normalize_enum(field, raw, dict, has_other, warnings)] if raw.present?
    end.to_h
  end

  def mirror_attrs(row)
    PRIMARY_CONTACT_MIRROR.transform_values { |src| row[src].to_s.strip.presence }.compact
  end

  # 建联系人：有姓名或邮箱才建。邮箱在账号内已存在则复用并挂到客户，避免唯一性冲突。
  def build_contact(customer, row, warnings)
    cname = row[:contact_name].to_s.strip
    email = row[:contact_email].to_s.strip.downcase
    return if cname.blank? && email.blank?
    return if link_existing_contact(customer, email, cname, warnings)

    create_contact!(customer, row, cname, email)
  rescue ActiveRecord::RecordInvalid => e
    warnings << "联系人未建：#{e.record.errors.full_messages.join('；')}"
  end

  def link_existing_contact(customer, email, cname, warnings)
    return false if email.blank?

    dup = @account.contacts.where('LOWER(email) = ?', email).first
    return false unless dup

    dup.update(crm_customer_id: customer.id, name: dup.name.presence || cname)
    warnings << "联系人邮箱 #{email} 已存在，已关联到本客户"
    true
  end

  def create_contact!(customer, row, cname, email)
    contact = @account.contacts.new(
      name: cname.presence || email, email: email.presence, crm_customer_id: customer.id
    )
    phone = row[:contact_phone].to_s.strip
    contact.phone_number = normalize_phone(phone) if phone.present?
    job = row[:contact_job_title].to_s.strip
    contact.additional_attributes = { job_title: job } if job.present?
    contact.save!
  end

  def normalize_enum(field, raw, dict, has_other, warnings)
    key = raw.to_s.strip
    upper = key.upcase
    # 已是合法英文码
    consts = Crm::Customer.const_get(enum_const(field))
    return upper if consts.include?(upper)

    hit = dict[key] || dict[key.downcase]
    return hit if hit

    warnings << "#{field_label(field)}「#{key}」未识别，已#{has_other ? '归为 OTHER' : '留空'}"
    has_other ? 'OTHER' : nil
  end

  def normalize_level(raw, warnings)
    v = raw.to_s.strip.upcase.gsub(/[类级\s]/, '')
    return v if Crm::Customer::CUSTOMER_LEVELS.include?(v)

    warnings << "客户等级「#{raw}」未识别，已留空"
    nil
  end

  def normalize_phone(phone)
    p = phone.gsub(/[^\d+]/, '')
    p.start_with?('+') ? p : "+#{p}"
  end

  def enum_const(field)
    { trade_country: :COUNTRIES, trade_region: :TRADE_REGIONS, industry: :INDUSTRIES,
      source_channel: :SOURCE_CHANNELS, customer_status: :CUSTOMER_STATUSES,
      currency_preference: :CURRENCIES, contact_preference: :CONTACT_PREFERENCES }[field]
  end

  def field_label(field)
    { trade_country: '国家', trade_region: '地区', industry: '行业', source_channel: '来源',
      customer_status: '状态', currency_preference: '币种', contact_preference: '联系偏好' }[field]
  end

  def owner_label(customer)
    return '🌊 公海' if customer.is_in_public_pool
    return "👤 #{customer.account_owner&.name}" if customer.account_owner_id

    '未分配'
  end

  def result(idx, name, status, message: nil, warnings: [])
    { row: idx + 1, name: name, status: status, message: message, warnings: warnings }
  end
end
