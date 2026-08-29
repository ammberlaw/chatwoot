# == Schema Information
#
# Table name: mes_bom_revisions
#
#  id            :bigint           not null, primary key
#  diff          :jsonb            not null
#  reason        :text
#  rev_no        :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  bom_id        :bigint           not null
#  changed_by_id :bigint
#
# Indexes
#
#  index_mes_bom_revisions_on_account_id             (account_id)
#  index_mes_bom_revisions_on_account_id_and_bom_id  (account_id,bom_id)
#  index_mes_bom_revisions_on_bom_id                 (bom_id)
#
# Foreign Keys
#
#  fk_rails_...  (bom_id => mes_boms.id) ON DELETE => cascade
#  fk_rails_...  (changed_by_id => users.id) ON DELETE => nullify
#
class Mes::BomRevision < ApplicationRecord
  belongs_to :account
  belongs_to :bom, class_name: 'Mes::Bom', inverse_of: :bom_revisions
  belongs_to :changed_by, class_name: 'User', optional: true

  # diff：每行一条变更 { kind: 'added'|'removed'|'changed', material_no, material_name,
  #                      from_qty, to_qty, unit }。空数组=无实质用料变更（不生成记录）。
  validates :rev_no, presence: true

  default_scope { order(rev_no: :desc) }
end
