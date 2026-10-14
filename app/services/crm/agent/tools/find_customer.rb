# 按关键词找客户。名字/编码/国家/邮箱/网站都能搜——业务员嘴里说的"Marco"可能是
# 客户名也可能是联系人名，一次都搜了省得来回问。
class Crm::Agent::Tools::FindCustomer < Crm::Agent::Tools::Base
  description '按关键词查找客户档案。关键词可以是客户名、客户编码、联系人名、邮箱、网站或国家。返回匹配到的客户清单（含客户ID），后续要看详情或往来邮件时用这个ID。'
  param :keyword, desc: '搜索关键词，例如客户名、邮箱或国家'
  param :limit, type: 'integer', desc: '最多返回几条，默认 10', required: false

  MATCH_SQL = <<~SQL.squish
    crm_customers.name ILIKE :t OR crm_customers.customer_code ILIKE :t
    OR crm_customers.primary_contact_name ILIKE :t OR crm_customers.contact_email ILIKE :t
    OR crm_customers.website ILIKE :t OR crm_customers.trade_country ILIKE :t
  SQL

  def execute(keyword:, limit: 10)
    rows = scope.customers.where(MATCH_SQL, t: "%#{keyword.to_s.strip}%")
                .order(last_deal_at: :desc, id: :desc).limit([limit.to_i, 25].min)
    return "没找到和「#{keyword}」相关的客户（只在你有权限看的范围内搜）。" if rows.empty?

    rows.map { |c| line(c) }.join("\n")
  end

  private

  def line(customer)
    "ID #{customer.id}｜#{customer.name}｜编码 #{customer.customer_code.presence || '—'}｜" \
      "#{customer.trade_country.presence || '国家未填'}｜" \
      "联系人 #{customer.primary_contact_name.presence || '—'} #{customer.contact_email}｜" \
      "成交 #{customer.deal_order_count.to_i} 单 #{money(customer.deal_total_amount_micros)}｜" \
      "最近成交 #{day(customer.last_deal_at)}"
  end
end
