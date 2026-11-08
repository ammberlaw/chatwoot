class AddDiscardAuditToCrmLeads < ActiveRecord::Migration[7.1]
  # 谁丢的、什么时候丢的。
  # 丢弃不只是「这条我不要」——它会喂给 AI 初筛的判例库（见 Crm::LeadScreenMemory），
  # 一个人批量乱丢能把整套初筛教歪，查不出是谁就没法纠。
  def change
    add_column :crm_leads, :discarded_by_id, :bigint
    add_column :crm_leads, :discarded_at, :datetime
  end
end
