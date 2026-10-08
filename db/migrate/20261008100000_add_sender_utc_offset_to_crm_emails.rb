# 发件人时区偏移（分钟）：邮件 Date 头本来就带着对方电脑的时区（+0200 / -0400），
# 入库时被 to_time 折成 UTC 扔掉了。存下来才能给**没建档的客户**算当地时间——
# 建档客户走档案国家（有完整时区规则、夏令时也准），这一列是其余所有人的兜底。
#
# 只对今后收到的邮件有效：老邮件的原始 Date 头没留存，补不回来。
class AddSenderUtcOffsetToCrmEmails < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_emails, :sender_utc_offset_minutes, :integer
  end
end
