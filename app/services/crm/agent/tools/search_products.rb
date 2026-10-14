# 产品档案查询。做报价/PI 时模型需要知道「这个型号叫什么、规格是什么、挂的售价多少」。
#
# 成本价不给模型——它会出现在对话里，而对话是业务员在看（生态硬约束：销售端不可见成本）。
class Crm::Agent::Tools::SearchProducts < Crm::Agent::Tools::Base
  description '查产品档案：按编码、名称或规格搜。用来做报价单或 PI 时确认型号、规格和售价。'
  param :keyword, desc: '产品编码、名称或规格关键词'
  param :limit, type: 'integer', desc: '最多返回几条，默认 10', required: false

  MATCH_SQL = 'crm_products.sku ILIKE :t OR crm_products.name ILIKE :t OR crm_products.specification ILIKE :t'.freeze

  def execute(keyword:, limit: 10)
    rows = scope.account.crm_products.where(is_active: true)
                .where(MATCH_SQL, t: "%#{keyword.to_s.strip}%")
                .order(:sku).limit([limit.to_i, 25].min)
    return "产品档案里没搜到「#{keyword}」。" if rows.empty?

    rows.map { |p| line(p) }.join("\n")
  end

  private

  def line(product)
    "#{product.sku}｜#{product.name}｜规格 #{product.specification.presence || '—'}｜" \
      "单位 #{product.unit.presence || '—'}｜售价 #{money(product.sale_price_micros, product.pricing_currency.presence || 'CNY')}"
  end
end
