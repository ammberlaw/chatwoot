module Crm
  # 账号级「系统通知」发送人：绩效下发 / 打分 / 月度提醒等 CRM 自动通知，
  # 以它的名义在团队沟通发消息（而非某个真人管理员）。按账号幂等，不作为坐席（不进 agent 列表）。
  class SystemUser
    NAME = '系统通知'.freeze

    def self.for(account)
      email = "crm-system-#{account.id}@wintouch.local"
      User.find_by(email: email) || create_for(email)
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
