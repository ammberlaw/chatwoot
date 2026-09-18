# 平板电脑/商显工控用 MES 的内置规格（前端 orderSpecFields.js），没有数据库模板行，
# 只记住用的是哪套规格，渲染时据此取字段定义。
class AddSpecTemplateToCrmQuoteRequests < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_quote_requests, :spec_template, :string
    change_column_null :crm_quote_requests, :template_id, true
  end
end
