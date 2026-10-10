# 缺价清单：生产任务单用料里，三级价源都查不到价的物料。
#
# 为什么要这个：成本覆盖率只告诉你「不全」，不告诉你「差哪些」。采购/财务要补价，
# 需要的是一张能照着干活的单子——哪个编码、叫什么、被多少张任务单用到。
# 按被用到的任务单数倒序，先补用得最多的那几颗，覆盖率涨得最快。
class Mes::MissingPriceFinder
  def initialize(account:)
    @account = account
  end

  # => [{ sku:, name:, specification:, unit:, bom_count:, total_qty: }, ...]
  def perform
    items = Mes::BomItem.where(account_id: @account.id).to_a
    return [] if items.empty?

    priced = Mes::MaterialPriceResolver.new(account: @account, items: items).perform
    missing = items.reject { |i| priced.key?(i.id) }
    group(missing)
  end

  private

  def group(missing)
    by_sku = missing.group_by { |i| i.material_no.to_s.strip }.except('')
    products = @account.crm_products.where(sku: by_sku.keys).index_by { |p| p.sku.to_s.strip }
    rows = by_sku.map { |sku, lines| summarize(sku, lines, products[sku]) }
    rows.sort_by { |r| [-r[:bom_count], r[:sku]] }
  end

  def summarize(sku, lines, product)
    first = lines.first
    { sku: sku,
      crm_product_id: product&.id,
      name: product&.name || first.material_name,
      specification: product&.specification || first.specification,
      unit: first.unit,
      bom_count: lines.map(&:bom_id).uniq.size,
      total_qty: lines.sum { |r| r.qty.to_d }.to_f }
  end
end
