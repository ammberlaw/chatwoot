module Crm
  # 账号级「系统通知」发送人：绩效下发 / 打分 / 月度提醒等 CRM 自动通知，
  # 以它的名义在团队沟通发消息（而非某个真人管理员）。按账号幂等，不作为坐席（不进 agent 列表）。
  class SystemUser
    NAME = '系统通知'.freeze

    def self.for(account)
      email = email_for(account.id)
      User.find_by(email: email) || create_for(email)
    end

    def self.email_for(account_id)
      "crm-system-#{account_id}@wintouch.local"
    end

    # 只读查 id：后台任务判定「这条消息是不是系统通知发的」用，查不到就是没有，别建号。
    def self.existing_id_for(account_id)
      User.where(email: email_for(account_id)).pick(:id)
    end

    def self.create_for(email)
      User.create!(
        name: NAME,
        email: email,
        password: "#{SecureRandom.alphanumeric(24)}Aa1!",
        confirmed_at: Time.current
      )
    rescue ActiveRecord::RecordNotUnique
      # 并发下别的进程刚建了，重新取即可。
      User.find_by(email: email)
    end
  end
end
