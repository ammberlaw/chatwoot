# 账套的「编制单位」：财务报表（会企01/02/03）表头要印的公司全称。
# 原先账套里根本没有公司名这一项，报表表头只能空着——打印/发给会计时看不出是哪家的账。
class AddCompanyNameToErpSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :erp_settings, :company_name, :string
  end
end
