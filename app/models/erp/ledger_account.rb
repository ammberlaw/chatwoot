# 会计科目（ERP 记账引擎的地基）。
# 编码体系走财政部《企业会计准则》国标：1 资产 / 2 负债 / 4 所有者权益 / 5 成本 / 6 损益，
# 与金蝶、用友同码——将来与金蝶平行跑账时科目可逐条对上（见 ERP_SPEC §8.1、E9 平行期）。
#
# 树形：is_group=true 的是分类节点（只汇总不记账），叶子科目才能挂分录行（凭证侧校验）。
# 余额方向 direction 决定报表取数与增减符号；备抵科目（累计折旧/坏账准备）方向与大类相反，故单列一字段。
# == Schema Information
#
# Table name: erp_ledger_accounts
#
#  id           :bigint           not null, primary key
#  account_type :string
#  bs_section   :string
#  category     :string           not null
#  code         :string           not null
#  currency     :string
#  dimensions   :jsonb            not null
#  direction    :string           not null
#  is_active    :boolean          default(TRUE), not null
#  is_group     :boolean          default(FALSE), not null
#  is_system    :boolean          default(FALSE), not null
#  name         :string           not null
#  position     :integer          default(0), not null
#  remark       :text
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  parent_id    :bigint
#
# Indexes
#
#  index_erp_ledger_accounts_on_account_id               (account_id)
#  index_erp_ledger_accounts_on_account_id_and_category  (account_id,category)
#  index_erp_ledger_accounts_on_account_id_and_code      (account_id,code) UNIQUE
#  index_erp_ledger_accounts_on_parent_id                (parent_id)
#
# Foreign Keys
#
#  fk_rails_...  (parent_id => erp_ledger_accounts.id) ON DELETE => restrict
#
class Erp::LedgerAccount < ApplicationRecord
  # 国标五大类。收入与费用同属「损益类(6)」，靠 direction 区分（收入贷方、费用借方），与金蝶一致。
  CATEGORIES = %w[ASSET LIABILITY EQUITY COST PL].freeze
  CATEGORY_LABELS = {
    'ASSET' => '资产类', 'LIABILITY' => '负债类', 'EQUITY' => '所有者权益类',
    'COST' => '成本类', 'PL' => '损益类'
  }.freeze

  DIRECTIONS = %w[DEBIT CREDIT].freeze

  # 业务钩子：自动凭证、报表、期末流程按 account_type 找科目，不靠中文名匹配。
  ACCOUNT_TYPES = %w[
    CASH BANK RECEIVABLE PAYABLE STOCK FIXED_ASSET ACCUM_DEPRECIATION
    TAX INCOME COGS EXPENSE DEPRECIATION EXCHANGE_DIFF ROUND_OFF
    STOCK_RECEIVED_NOT_BILLED STOCK_ADJUSTMENT YEAR_PROFIT
  ].freeze

  # 分录行可带的管理维度（比金蝶强的点：维度明细账，见 §9.1）。
  DIMENSIONS = %w[customer supplier order department member].freeze
  DIMENSION_LABELS = {
    'customer' => '客户', 'supplier' => '供应商', 'order' => '订单',
    'department' => '部门', 'member' => '业务员'
  }.freeze

  # 必填维度只卡往来科目：应收必须挂客户、应付必须挂供应商，否则往来对账查不出「谁欠我多少」。
  # 其余维度是「可填」，给毛利/费用分析用，不硬拦财务录凭证。
  REQUIRED_DIMENSION_BY_TYPE = { 'RECEIVABLE' => 'customer', 'PAYABLE' => 'supplier' }.freeze

  # 资产负债表归属段（报表按此分组出行，不靠树层级猜）。
  BS_SECTIONS = %w[CURRENT_ASSET NON_CURRENT_ASSET CURRENT_LIABILITY NON_CURRENT_LIABILITY EQUITY].freeze

  belongs_to :account
  belongs_to :parent, class_name: 'Erp::LedgerAccount', optional: true
  has_many :children, class_name: 'Erp::LedgerAccount', foreign_key: :parent_id, dependent: :restrict_with_error,
                      inverse_of: :parent

  validates :code, presence: true, uniqueness: { scope: :account_id }
  validates :name, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :account_type, inclusion: { in: ACCOUNT_TYPES }, allow_blank: true
  validates :bs_section, inclusion: { in: BS_SECTIONS }, allow_blank: true
  validate :validate_parent
  validate :validate_dimensions

  # prepend：抢在 dependent: :restrict_with_error 之前跑，否则报错是英文 i18n 缺失串，不是给财务看的中文提示。
  before_destroy :ensure_deletable, prepend: true

  scope :active, -> { where(is_active: true) }
  scope :leaves, -> { where(is_group: false) }

  # 记账用：只有启用中的叶子科目能挂分录行。
  def postable?
    is_active? && !is_group?
  end

  def label
    "#{code} #{name}"
  end

  # 该科目录凭证时必须带的维度（往来科目才有），nil＝无强制。
  def required_dimension
    REQUIRED_DIMENSION_BY_TYPE[account_type]
  end

  # 祖先链（含自身），面包屑/报表层级展开用。
  def ancestry_chain
    chain = [self]
    node = self
    chain.unshift(node = node.parent) while node.parent_id.present?
    chain
  end

  private

  def validate_parent
    return if parent_id.blank?
    return errors.add(:parent_id, '不能把自己设为上级科目') if parent_id == id

    parent_record = self.class.find_by(id: parent_id, account_id: account_id)
    return errors.add(:parent_id, '上级科目不存在') if parent_record.blank?

    validate_against_parent(parent_record)
  end

  def validate_against_parent(parent_record)
    return errors.add(:parent_id, '上级必须是分类科目（可挂明细）') unless parent_record.is_group?
    return errors.add(:category, '科目类别必须与上级一致') if parent_record.category != category
    # 国标编码是层层前缀（1002 在 1 下、660301 在 6603 下）；破了前缀，报表层级展开就乱。
    return errors.add(:code, "编码须以上级科目编码「#{parent_record.code}」开头") unless code.to_s.start_with?(parent_record.code.to_s)

    errors.add(:parent_id, '上级科目不能是自己的下级') if descendant_ids.include?(parent_id)
  end

  def descendant_ids
    return [] if id.blank?

    ids = []
    frontier = [id]
    while frontier.any?
      next_ids = self.class.where(account_id: account_id, parent_id: frontier).pluck(:id)
      ids.concat(next_ids)
      frontier = next_ids
    end
    ids
  end

  def validate_dimensions
    return if dimensions.blank?

    invalid = Array(dimensions).map(&:to_s) - DIMENSIONS
    errors.add(:dimensions, "不支持的维度：#{invalid.join('、')}") if invalid.any?
  end

  def ensure_deletable
    if is_system?
      errors.add(:base, '标准科目不可删除，可停用')
      throw(:abort)
    end
    return if children.empty?

    errors.add(:base, '该科目下还有明细科目，不能删除')
    throw(:abort)
  end
end
