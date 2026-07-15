# CRM「公司资料」与文档中心「销售资料」板块同步共享（同一份数据两个入口）：
# 1) 存量文档中心「销售资料」板块文档归一到 SALES 库；
# 2) 存量 SALES 公司文档补上「销售资料」板块归属。
class ShareSalesDocsBetweenCrmAndDocCenter < ActiveRecord::Migration[7.1]
  def up
    Crm::DocSection.where(name: '销售资料').find_each do |section|
      Crm::KnowledgeDoc.where(account_id: section.account_id, library: 'GENERAL', section_id: section.id)
                       .update_all(library: 'SALES') # rubocop:disable Rails/SkipsModelValidations
      Crm::KnowledgeDoc.where(account_id: section.account_id, library: 'SALES', scope: 'COMPANY', section_id: nil)
                       .update_all(section_id: section.id) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def down; end
end
