# 账套级财务政策（每账户一行）。目前承载坏账计提比例。
# == Schema Information
#
# Table name: erp_settings
#
#  id                      :bigint           not null, primary key
#  amount_includes_tax     :boolean          default(TRUE), not null
#  bad_debt_rates          :jsonb            not null
#  default_output_tax_rate :integer          default(13), not null
#  fiscal_start_date       :date
#  inventory_account_map   :jsonb            not null
#  receivables_enabled     :boolean          default(FALSE), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#
# Indexes
#
#  index_erp_settings_on_account_id  (account_id) UNIQUE
#
class Erp::Setting < ApplicationRecord
  # 账龄段 → 计提比例（百分数）。默认值是常见做法，不是准则强制——
  # 具体比例由财务按公司会计政策定，审计要看的是「按既定政策一贯执行」。
  DEFAULT_BAD_DEBT_RATES = {
    'D30' => 0, 'D60' => 1, 'D90' => 2, 'D180' => 5, 'D365' => 10, 'OVER' => 30
  }.freeze

  belongs_to :account

  validates :account_id, uniqueness: true
  # 税率是每张收入凭证的拆分依据，错一次全账跟着错；接口直调绕过界面时这里兜住。
  validate :output_tax_rate_in_range

  def self.for_account(account)
    find_by(account_id: account.id) || new(account: account)
  end

  # 应收台账是否已启用。过渡期账还在金蝶，这里是 false——
  # 此时销售订单「出货即完结」，不等应收收清（见 Erp::OrderCompletionService）。
  # 正式切过来那天把 erp_settings.receivables_enabled 置 true 即可，不用改代码。
  def self.receivables_enabled?(account)
    for_account(account).receivables_enabled
  end

  def output_tax_rate_in_range
    return if default_output_tax_rate.to_i.between?(0, 100)

    errors.add(:base, '销项税率必须是 0 到 100 之间的整数')
  end

  def bad_debt_rate_table
    DEFAULT_BAD_DEBT_RATES.merge(bad_debt_rates.presence || {})
  end

  # ── 存货科目映射（采购入库凭证的借方科目）──────────────────────────
  # 产品档案的「来源类别」(crm_products.source_category) → 存货科目编码。
  # 只给这三个选项；没配过的类别一律落原材料——新类别不会把账做错，
  # 最多是记粗了，财务在映射页补一条即可（口径见 ERP_SPEC §8.2bis）。
  RAW_MATERIAL_CODE = '1403'.freeze
  FINISHED_GOODS_CODE = '1405'.freeze
  SUBCONTRACT_CODE = '1408'.freeze
  INVENTORY_ACCOUNT_CODES = [RAW_MATERIAL_CODE, FINISHED_GOODS_CODE, SUBCONTRACT_CODE].freeze

  # 预置：把「看着就是成品」的类别挑出来落库存商品，其余留默认。
  # 匹配而不是枚举——各尺寸成品（10.1寸成品/7寸成品…）有二十几种写法，列不全。
  FINISHED_GOODS_PATTERNS = [/成品/, /外购机/, /\A裸机\z/, /闺蜜机/].freeze
  SUBCONTRACT_PATTERNS = [/委托加工/, /委外/].freeze

  def inventory_account_code_for(source_category)
    key = source_category.to_s.strip
    return RAW_MATERIAL_CODE if key.blank?

    code = inventory_account_map[key]
    INVENTORY_ACCOUNT_CODES.include?(code) ? code : RAW_MATERIAL_CODE
  end

  # 按模式给一个类别猜默认科目，供映射页「一键预置」用（人可逐条改）。
  def self.suggest_inventory_code(source_category)
    key = source_category.to_s.strip
    return SUBCONTRACT_CODE if SUBCONTRACT_PATTERNS.any? { |re| key.match?(re) }
    return FINISHED_GOODS_CODE if FINISHED_GOODS_PATTERNS.any? { |re| key.match?(re) }

    RAW_MATERIAL_CODE
  end
end
