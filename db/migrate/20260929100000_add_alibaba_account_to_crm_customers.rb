# 阿里买家账号（国际站 loginId / TM 号）：多店铺之间防撞单的钥匙。
# 阿里把买家邮箱藏了，邮箱/电话都常年为空（生产上 1978 个客户三样全空），
# 只有买家账号在后台页面上永远可见，故以它作为阿里来源客户的唯一身份。
class AddAlibabaAccountToCrmCustomers < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_customers, :alibaba_account, :string
    # 查重按 (account_id, 小写账号) 命中，唯一性不在库层强制：
    # 历史数据可能已有重复，建档时由查重接口拦截即可。
    add_index :crm_customers, 'account_id, LOWER(alibaba_account)',
              name: 'index_crm_customers_on_account_id_and_alibaba_account'
  end
end
