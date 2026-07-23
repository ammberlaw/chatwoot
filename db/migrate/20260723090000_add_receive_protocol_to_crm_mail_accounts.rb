class AddReceiveProtocolToCrmMailAccounts < ActiveRecord::Migration[7.1]
  # 收件协议：IMAP（默认）或 POP3。用于服务商关闭 IMAP、仅放开 POP3 的账户（如部分阿里企业邮）。
  def change
    add_column :crm_mail_accounts, :receive_protocol, :string, null: false, default: 'IMAP'
  end
end
