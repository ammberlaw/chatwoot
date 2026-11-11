# 生产报工（阶段 6，按数量批量报工 · 车间 PC 录入）。
# == Schema Information
#
# Table name: mes_production_records
#
#  id                  :bigint           not null, primary key
#  operation_name      :string
#  product_line        :string
#  qty_completed       :decimal(14, 3)   default(0.0), not null
#  qty_returned        :decimal(14, 3)   default(0.0), not null
#  qty_scrap           :decimal(14, 3)   default(0.0), not null
#  recorded_at         :datetime
#  remark              :text
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  operator_id         :bigint
#  production_order_id :bigint           not null
#
# Indexes
#
#  index_mes_production_records_on_account_and_product_line  (account_id,product_line)
#  index_mes_production_records_on_account_id                (account_id)
#  index_mes_production_records_on_operator_id               (operator_id)
#  index_mes_production_records_on_production_order_id       (production_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (operator_id => users.id) ON DELETE => nullify
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => cascade
#
class Mes::ProductionRecord < ApplicationRecord
  include Mes::LineScoped
  include Mes::Returnable

  belongs_to :account
  belongs_to :production_order, class_name: 'Mes::ProductionOrder'
  belongs_to :operator, class_name: 'User', optional: true

  before_validation :inherit_account
  before_validation :stamp_recorded_at, on: :create
  before_create :lock_and_recheck_order!
  after_create :apply_to_production_order
  after_destroy :revert_from_production_order

  validates :qty_completed, numericality: { greater_than_or_equal_to: 0 }
  validates :qty_returned, :qty_scrap, numericality: { greater_than_or_equal_to: 0 }
  # 禁止重复/超量报工：本次完成数不得让累计已产超过订单数量（报满即不能再报）。
  validate :within_order_remaining, on: :create
  # 流程硬锁：报工须已完成生产领料（订单到「生产领料」及以后）；外购订单不做报工。
  validate :enforce_stage_prerequisite, on: :create

  # ── 单据退回（Mes::Returnable）──：退回目标 = 生产领料板块（料不对退回仓库/领料）。
  # 报工无过账态、无单号，恒可退，单号用 报工#id。
  def document_board_key = 'mes_production_records_index'
  def return_document_label = '生产报工单'
  def return_document_no = "报工##{id}"
  def returnable? = true

  private

  # save 的事务持有订单锁直至提交，重新校验和累加产量不能被另一条报工穿插。
  def lock_and_recheck_order!
    production_order.lock!
    within_order_remaining
    enforce_stage_prerequisite
    raise ActiveRecord::RecordInvalid, self if errors.any?
  end

  def inherit_account
    self.account_id ||= production_order&.account_id
  end

  def product_line_source = production_order

  def stamp_recorded_at
    self.recorded_at ||= Time.current
  end

  # 流程硬锁：没领料/外购订单不能报工（前端也会隐藏不可选订单，此处为后端兜底）。
  def enforce_stage_prerequisite
    po = production_order
    return if po.nil?

    if po.outsourced?
      errors.add(:base, '外购订单不做生产报工：外购成品经「采购 → 收货」直接入成品仓')
    elsif po.status != 'IN_PROGRESS'
      errors.add(:base, '生产订单不在「进行中」状态（已完成/已停止/已作废），不可报工')
    elsif !po.stage_reached?('PICKING')
      stage_cn = Mes::ProductionOrder::STAGE_LABELS[po.stage] || po.stage
      errors.add(:base, "生产订单当前在「#{stage_cn}」阶段，需先完成生产领料才能报工")
    end
  end

  # 报工累加已产数量并推进阶段（首次报工 PICKING → PRODUCTION），
  # 有实际产出则通知仓库来做成品入库（全部/部分完工都推）。
  def apply_to_production_order
    production_order.add_produced!(qty_completed)
    production_order.notify_fg_inbound_ready(qty_completed, actor: operator) if qty_completed.to_d.positive?
  end

  # 删除报工（如清理重复报工）时把已产数量回退，避免 produced_qty 被灌大。
  def revert_from_production_order
    production_order&.remove_produced!(qty_completed)
  end

  # 累计已产 + 本次完成数 不得超过订单数量：挡住同一订单重复报工/超量报工。
  def within_order_remaining
    return if production_order.nil? || qty_completed.to_d <= 0

    remaining = [production_order.qty.to_d - production_order.produced_qty.to_d, 0].max
    return if qty_completed.to_d <= remaining

    errors.add(:qty_completed, over_report_message(remaining))
  end

  def over_report_message(remaining)
    "本次报工 #{fmt(qty_completed)} 超过订单剩余可报数量 #{fmt(remaining)}" \
      "（已产 #{fmt(production_order.produced_qty)}/#{fmt(production_order.qty)}），不能重复或超量报工"
  end

  def fmt(num)
    n = num.to_d
    (n == n.to_i ? n.to_i : n).to_s
  end
end
