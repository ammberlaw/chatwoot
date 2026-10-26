# 公司背调留痕。
#
# AI 背调（Crm::CompanyLookupService：抓官网 + Apollo 概况）一直是**实时查、不落库**的——
# 结果渲染到前端就没了，客户身上不留任何痕迹。于是绩效考核里「客户信息完整（含公司背调）」
# 这一项系统判不了，只能让主管人工看。
#
# 存两样：什么时候背调的、结论摘要。摘要留着是为了下次打开客户不用重查一遍
# （Apollo 是收费接口，重复查既慢又费额度）。
class AddBgCheckToCrmCustomers < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_customers, :bg_checked_at, :datetime
    add_column :crm_customers, :bg_summary, :text
  end
end
