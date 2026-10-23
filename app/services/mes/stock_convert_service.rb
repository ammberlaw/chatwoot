# 原料↔成品转换：把同一批货在 MES 的两本数量账之间换个身份。
#
# 为什么需要：采购入库永远落原料账（item_type=MATERIAL），销售出库永远从成品账扣（PRODUCT）。
# 整机外购转卖、或同一个屏既当零件又整台卖的货，买进来在原料账、要卖却得从成品账扣。
# 以前只能手开两张互不相干的单（原料出一张、成品进一张），台账上看着像库存被人改了。
#
# 一次转换＝一张 CONVERT_* 库存单，单里一个商品两行（一进一出，数量相等），建完直接过账。
# 草稿态没有意义：转换是个瞬时动作，不像收货要等实物、不像出库要等审核。
class Mes::StockConvertService
  class ConvertError < StandardError; end

  DIRECTIONS = {
    'TO_PRODUCT' => { purpose: 'CONVERT_TO_PRODUCT', from: 'MATERIAL', to: 'PRODUCT' },
    'TO_MATERIAL' => { purpose: 'CONVERT_TO_MATERIAL', from: 'PRODUCT', to: 'MATERIAL' }
  }.freeze

  # rubocop:disable Metrics/ParameterLists -- 参数摊开比塞进 hash 让调用方猜键名清楚
  def initialize(account:, actor:, direction:, warehouse_id:, lines:, remark: nil)
    @account = account
    @actor = actor
    @dir = DIRECTIONS[direction.to_s]
    @warehouse_id = warehouse_id.presence && warehouse_id.to_i
    @lines = Array(lines)
    @remark = remark
  end
  # rubocop:enable Metrics/ParameterLists

  def perform
    raise ConvertError, '转换方向不对' if @dir.nil?
    raise ConvertError, '请选择仓库' if @warehouse_id.blank?

    rows = normalized_lines
    raise ConvertError, '请至少选择一个商品并填写数量' if rows.empty?

    # 建单与过账同一事务：过账失败（最常见是源账数量不够）要连单子一起回滚。
    # 否则列表里会留下一张「没真发生过的转换」的草稿单，而转换本来就没有草稿这个状态。
    ApplicationRecord.transaction do
      entry = build_entry(rows)
      entry.post!
      entry
    end
  end

  private

  # 同一个商品被填了两次就合并，否则配对校验会判成「一个商品四行」。
  def normalized_lines
    @lines.filter_map { |l| [l[:crm_product_id].to_i, l[:qty].to_d] }
          .select { |pid, qty| pid.positive? && qty.positive? }
          .group_by(&:first)
          .map { |pid, pairs| [pid, pairs.sum(&:last)] }
  end

  def build_entry(rows)
    @account.mes_stock_entries.create!(
      purpose: @dir[:purpose], owner_id: @actor.id, remark: @remark,
      # 同仓转换：成本层按 (商品, 仓库) 记，换仓会让数量账和成本层分家。要挪仓走移仓单。
      from_warehouse_id: @warehouse_id, to_warehouse_id: @warehouse_id,
      product_line: nil,
      stock_entry_items_attributes: rows.flat_map { |pid, qty| pair_attributes(pid, qty) }
    )
  rescue ActiveRecord::RecordInvalid => e
    raise ConvertError, e.record.errors.full_messages.join('；')
  end

  def pair_attributes(product_id, qty)
    [@dir[:from], @dir[:to]].map do |item_type|
      { item_type: item_type, crm_product_id: product_id, qty: qty, warehouse_id: @warehouse_id }
    end
  end
end
