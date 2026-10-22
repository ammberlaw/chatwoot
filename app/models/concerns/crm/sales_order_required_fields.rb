# 建单必填项。
#
# 都只校验 create，不校验 update——存量老单缺什么是历史，编辑时一并卡死
# 等于逼业务员改个交期都要先回填一堆历史信息，那不是补数据，是挡着他干活。
# 老单缺的东西在订单详情面板上照常标出来，补不补由审核人和他自己决定。
#
# 自动转进来的单（PI 付款转单、报价单转单）带 system_generated，整组跳过：
# 那几条路的字段是从上游单据抄的，抄不到也不该把单卡在系统外。
module Crm::SalesOrderRequiredFields
  extend ActiveSupport::Concern

  included do
    validate :require_attachment_on_create, on: :create, unless: :system_generated
    validate :require_order_kind_on_create, on: :create, unless: :system_generated
    validate :require_line_items_on_create, on: :create, unless: :system_generated
    validate :require_settlement_on_create, on: :create, unless: :system_generated
  end

  private

  # 新建订单必须至少上传一个附件（如 PI、生产订单）。
  def require_attachment_on_create
    errors.add(:files, '请至少上传一个附件（如 PI、生产订单）') unless files.attached?
  end

  # 订单类型决定这单往下走哪条线（定制→MES 生产订单 / 库存→现货出库单）。
  # 金蝶过渡期它还兼当「这单在哪套系统结算」的标记，空着下游就无从分流，故人工建单必选。
  def require_order_kind_on_create
    errors.add(:order_kind, '请选择订单类型（定制单/库存单）') if order_kind.blank?
  end

  # 订单明细必填（2026-10-22）：以前可以一行不填，审核人打开只看到一个金额，
  # 不知道这单卖的是什么货，只能退回去问业务员。生产上 365 张单里 15 张是空的。
  def require_line_items_on_create
    filled = Array(line_items).count do |item|
      next false unless item.is_a?(Hash)

      item['name'].to_s.strip.present? && item['quantity'].to_d.positive? && item['unit_price'].present?
    end
    return if filled.positive?

    errors.add(:line_items, '请填写订单明细：至少一行，写清品名、数量、单价')
  end

  # 结算方式 + 收款账户 + 交货方式必填（2026-10-22）：钱怎么收、收到哪个账户，
  # 财务建账和对账要靠前两项；货怎么送到客户手上，仓管备货派车要靠第三项。
  # 生产上 9 月前的老单九成这几栏是空的（367 张里 329 张没结算方式），所以只卡新建。
  def require_settlement_on_create
    errors.add(:payment_term, '请选择结算方式') if payment_term.blank?
    errors.add(:receipt_account_id, '请选择收款账户') if receipt_account_id.blank?
    errors.add(:delivery_method, '请选择交货方式') if delivery_method.blank?
  end
end
