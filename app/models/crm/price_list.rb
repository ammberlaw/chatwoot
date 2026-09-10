# 核价表（内部报价单）的一个版本。主管/财务改价 = 发一版新的，业务员看最新已发布版。
# 列由每张表自己定义（columns: [{label,type}]，type=text/price），明细行的 values 按列顺序对应。
# 各产品线的表结构差异很大：平板是「型号+规格+三档量价」，D/L 系列有六七列参数，
# 水牌机按触摸类型横向列价（根本不是数量分档），背包屏还多几列加价——写死列装不下。
# == Schema Information
#
# Table name: crm_price_lists
#
#  id              :bigint           not null, primary key
#  columns         :jsonb            not null
#  currency        :string           default("USD"), not null
#  effective_on    :date
#  footer_name     :string
#  header_note     :text
#  product_line    :string           not null
#  published_at    :datetime
#  rules_note      :text
#  status          :string           default("DRAFT"), not null
#  title           :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  creator_id      :bigint
#  published_by_id :bigint
#
# Indexes
#
#  index_crm_price_lists_on_account_line_status  (account_id,product_line,status)
#  index_crm_price_lists_on_account_status_date  (account_id,status,effective_on)
#
class Crm::PriceList < ApplicationRecord
  self.table_name = 'crm_price_lists'

  STATUSES = { 'DRAFT' => '草稿', 'PUBLISHED' => '已发布', 'ARCHIVED' => '已归档' }.freeze
  CURRENCIES = %w[USD CNY EUR].freeze

  belongs_to :account
  belongs_to :creator, class_name: 'User', optional: true
  belongs_to :published_by, class_name: 'User', optional: true
  has_many :items, class_name: 'Crm::PriceListItem', foreign_key: :crm_price_list_id,
                   inverse_of: :price_list, dependent: :destroy

  validates :title, presence: true
  validates :product_line, presence: true
  validates :status, inclusion: { in: STATUSES.keys }
  validates :currency, inclusion: { in: CURRENCIES }

  scope :published, -> { where(status: 'PUBLISHED') }
  scope :for_line, ->(line) { where(product_line: line) }

  # 列定义容错：老数据或手工写坏时至少给一列，避免前端渲染成空表。
  def column_defs
    defs = Array(columns).filter_map do |c|
      next if c['label'].blank?

      { 'label' => c['label'], 'type' => c['type'] == 'price' ? 'price' : 'text' }
    end
    defs.presence || [{ 'label' => '型号', 'type' => 'text' }]
  end
  # 生效日相同再按 id：同一天补发第二版时以后发的为准。
  scope :newest_first, -> { order(Arel.sql('effective_on DESC NULLS LAST, id DESC')) }

  def status_label = STATUSES[status]

  # 导出文件名：跟公司原来的 Excel 一个习惯（2026.4.18外贸平板内部报价单）。
  def export_basename
    date = (effective_on || created_at.to_date).strftime('%Y.%-m.%-d')
    "#{date}#{title}"
  end

  # 发布：同一条产品线同时只保留一版「已发布」，旧的自动归档——业务员进来永远只看到一张有效表。
  # 归档只在本产品线内进行，平板发新版不会把商显那张顶掉。
  def publish!(user)
    transaction do
      account.crm_price_lists.for_line(product_line).published.where.not(id: id)
             .update_all(status: 'ARCHIVED', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      update!(status: 'PUBLISHED', published_by: user, published_at: Time.current)
    end
  end

  # 从本版复制出一份草稿（调价时不用重录二十几行）。
  def duplicate_as_draft(user)
    copy = account.crm_price_lists.create!(
      title: title, product_line: product_line, currency: currency, columns: columns,
      header_note: header_note, rules_note: rules_note, footer_name: footer_name,
      effective_on: Date.current, status: 'DRAFT', creator: user
    )
    items.order(:position).each do |item|
      copy.items.create!(account_id: account_id, position: item.position,
                         values: item.values, remark: item.remark)
    end
    copy
  end
end
