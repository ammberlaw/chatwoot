# 定制报价的参数模板：每条产品线一套字段（平板一套、商显一套）。
# form_fields 结构与 OA 审批模板一致，前端那套动态表单渲染直接复用：
#   [{ key:, label:, type: 'text'|'number'|'textarea'|'select'|'date', required:, options: [] }]
# == Schema Information
#
# Table name: crm_quote_request_templates
#
#  id           :bigint           not null, primary key
#  active       :boolean          default(TRUE), not null
#  description  :string
#  form_fields  :jsonb            not null
#  name         :string           not null
#  position     :integer          default(0), not null
#  product_line :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  creator_id   :bigint
#
# Indexes
#
#  idx_crm_qr_templates_line                        (account_id,product_line,active)
#  index_crm_quote_request_templates_on_account_id  (account_id)
#
class Crm::QuoteRequestTemplate < ApplicationRecord
  belongs_to :account
  belongs_to :creator, class_name: 'User', optional: true
  has_many :quote_requests, class_name: 'Crm::QuoteRequest', foreign_key: :template_id,
                            dependent: :restrict_with_error, inverse_of: :template

  audited

  validates :product_line, :name, presence: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  FIELD_TYPES = %w[text number textarea select date].freeze

  validate :form_fields_shape

  private

  # 字段定义必须能被前端渲染：key/label 不能空，type 要在白名单里。
  # 配错了这里拦下，好过业务员打开表单看到一片空白。
  def form_fields_shape
    Array(form_fields).each_with_index do |f, i|
      errors.add(:form_fields, "第 #{i + 1} 个字段缺 key 或 label") if f['key'].blank? || f['label'].blank?
      errors.add(:form_fields, "第 #{i + 1} 个字段类型不支持：#{f['type']}") unless FIELD_TYPES.include?(f['type'].to_s)
    end
  end
end
