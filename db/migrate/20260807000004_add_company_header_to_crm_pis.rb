class AddCompanyHeaderToCrmPis < ActiveRecord::Migration[7.1]
  def change
    # 所选公司抬头的 key（对应 Crm::PiTemplateFiller::COMPANY_HEADERS）；
    # 导出时按 key 取该主体的公司名/地址/银行信息填模板。
    add_column :crm_pis, :company_header, :string
  end
end
