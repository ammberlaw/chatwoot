# 客户的欧盟增值税号。
#
# 为什么值得单独开一列：开 PI 做欧盟 B2B 反向征税要这个号，现在是业务员发邮件问客户要、
# 来回几封。而它本来就印在对方官网的法律信息页上（欧盟各国强制公示），
# 背调抓那一页的时候顺手就能拿到。
#
# vat_verified_at 有值 = 通过欧盟官方 VIES 验证过。**没验过的号一律不写进来**——
# 这个号要印到形式发票上，错一个数字就是报关的事。
class AddVatNoToCrmCustomers < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_customers, :vat_no, :string
    add_column :crm_customers, :vat_verified_at, :datetime
  end
end
