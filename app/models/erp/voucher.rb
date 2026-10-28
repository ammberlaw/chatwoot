# 记账凭证：会计系统的原子单据。中式凭证 = 凭证字号（记-2026-08-0001）+ 逐行摘要 + 借贷分录。
#
# 状态机：DRAFT 待过账 →（借贷平衡校验通过）→ POSTED 已记账 → 只能红冲，不能改删；
# DRAFT 可改可删可作废（VOID）。账簿/报表只认 POSTED 的分录行（见 §9.1 实时查询不落中间表）。
# == Schema Information
#
# Table name: erp_vouchers
#
#  id                  :bigint           not null, primary key
#  attachment_count    :integer          default(0), not null
#  period              :string           not null
#  posted_at           :datetime
#  remark              :text
#  source_type         :string
#  status              :string           default("DRAFT"), not null
#  summary             :string
#  total_credit_micros :bigint           default(0), not null
#  total_debit_micros  :bigint           default(0), not null
#  voucher_date        :date             not null
#  voucher_no          :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  posted_by_id        :bigint
#  prepared_by_id      :bigint
#  reversal_of_id      :bigint
#  source_id           :bigint
#
# Indexes
#
#  index_erp_vouchers_on_account_id                   (account_id)
#  index_erp_vouchers_on_account_id_and_period        (account_id,period)
#  index_erp_vouchers_on_account_id_and_status        (account_id,status)
#  index_erp_vouchers_on_account_id_and_voucher_date  (account_id,voucher_date)
#  index_erp_vouchers_on_account_id_and_voucher_no    (account_id,voucher_no) UNIQUE
#  index_erp_vouchers_on_reversal_of_id               (reversal_of_id)
#  index_erp_vouchers_on_source_type_and_source_id    (source_type,source_id)
#  uniq_erp_voucher_draft_source                      (account_id,source_type,source_id) UNIQUE WHERE ((source_id IS NOT NULL) AND ((status)::text = 'DRAFT'::text))
#  uniq_erp_voucher_reversal                          (account_id,reversal_of_id) UNIQUE WHERE (reversal_of_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (reversal_of_id => erp_vouchers.id) ON DELETE => nullify
#
class Erp::Voucher < ApplicationRecord
  DRAFT = 'DRAFT'.freeze
  POSTED = 'POSTED'.freeze
  VOID = 'VOID'.freeze
  STATUSES = [DRAFT, POSTED, VOID].freeze
  STATUS_LABELS = { DRAFT => '待过账', POSTED => '已记账', VOID => '已作废' }.freeze

  # 期末结转凭证由结账流程自己生成，绕过期间冻结校验（否则结账时自己拦自己）。
  attr_accessor :skip_period_guard

  belongs_to :account
  belongs_to :prepared_by, class_name: 'User', optional: true
  belongs_to :posted_by, class_name: 'User', optional: true
  belongs_to :reversal_of, class_name: 'Erp::Voucher', optional: true
  has_one :reversed_by, class_name: 'Erp::Voucher', foreign_key: :reversal_of_id, inverse_of: :reversal_of,
                        dependent: :nullify
  has_many :lines, -> { order(:position, :id) }, class_name: 'Erp::VoucherLine', foreign_key: :voucher_id,
                                                 dependent: :destroy, inverse_of: :voucher

  accepts_nested_attributes_for :lines, allow_destroy: true

  # 原始单据影像（发票、水单、报销单扫描件）。已过账凭证也允许补传——
  # 补一张扫描件不改变账，不该逼财务去红冲重做。
  has_many_attached :documents

  validates :voucher_no, presence: true, uniqueness: { scope: :account_id }
  validates :voucher_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :validate_period_open

  before_validation :assign_period
  before_validation :assign_voucher_no, on: :create

  scope :posted, -> { where(status: POSTED) }
  scope :in_period, ->(period) { where(period: period) }

  def editable?
    status == DRAFT
  end

  # 能不能删。
  #
  # 草稿和已作废：随便删。作废只对草稿开放（VouchersController#void 要求 editable?），
  # 所以 VOID 那张从头到尾没碰过总账。
  #
  # 已记账(POSTED)：2026-10-28 起也允许删（财务要求）。能放开是因为账簿和报表
  # 全部**实时按 POSTED 凭证算、不落中间表**（见 Erp::LedgerQueryService），
  # 删掉余额自己就跟着变，不会留下对不上的中间结果。
  # 但下面三种必须挡住，否则账会悄悄不平：
  #   ① 期间已结账——报表已经出过、可能已报给老板或税局，删了历史数字就变了
  #   ② 已被红冲——红冲单还挂着指向它，删了红冲单就成了无源之水，等于凭空多一笔
  #   ③ 它自己是红冲单——删了原凭证就回到"未冲"状态，但 reversed_by 已经指过去，
  #      界面上显示已红冲、账上却是原样
  def deletable?
    return true if status == DRAFT || status == VOID
    return false unless status == POSTED

    delete_blocker.blank?
  end

  # 不能删的理由（给用户看的人话）。nil＝可以删。
  def delete_blocker
    return nil unless status == POSTED

    if Erp::FiscalPeriod.closed?(account, period)
      "#{period} 已结账，期间冻结后不能删凭证。要改先反结账。"
    elsif reversed_by.present?
      "这张已被 #{reversed_by.voucher_no} 红冲过，删了红冲单会变成无源之水。要删请先删红冲单。"
    elsif reversal_of_id.present?
      '这张是红冲单，删了会让被冲的那张回到「未冲」状态但界面仍显示已红冲。请改用其它方式更正。'
    end
  end

  def balanced?
    total_debit_micros == total_credit_micros && total_debit_micros.positive?
  end

  # 借贷合计（本位币）随分录行落库刷新，列表与平衡校验都读它。
  # 有意跳校验/回调：这是分录行算出来的缓存合计，走 save 会连带重跑分录校验与字号生成。
  def refresh_totals!
    grouped = lines.reject(&:marked_for_destruction?).group_by(&:direction)
    update_columns( # rubocop:disable Rails/SkipsModelValidations
      total_debit_micros: sum_base(grouped[Erp::VoucherLine::DEBIT]),
      total_credit_micros: sum_base(grouped[Erp::VoucherLine::CREDIT]),
      updated_at: Time.current
    )
  end

  private

  # 已结账期间冻结（§13-6）：该期间的凭证不许新增/修改。
  # 期末结转凭证本身是结账过程生成的，用 skip_period_guard 放行。
  def validate_period_open
    return if skip_period_guard
    return if period.blank?
    return unless Erp::FiscalPeriod.closed?(account, period)

    errors.add(:base, "会计期间 #{period} 已结账，凭证已冻结；要改请先由管理员反结账")
  end

  def sum_base(rows)
    Array(rows).sum { |line| line.base_amount_micros.to_i }
  end

  def assign_period
    self.period = voucher_date.strftime('%Y-%m') if voucher_date.present?
  end

  # 记-YYYY-MM-####：按月连续编号，与金蝶/用友的「记字第N号」同习惯。
  # 取号并发安全（advisory lock + 序号按数值取最大），见 Erp::SequenceAllocator。
  def assign_voucher_no
    return if voucher_no.present? || voucher_date.blank?

    self.voucher_no = Erp::SequenceAllocator.next_number(
      account, account.erp_vouchers, :voucher_no, "记-#{period}-", 4
    )
  end
end
