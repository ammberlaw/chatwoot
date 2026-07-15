# 敏感区访问许可（员工档案/薪资配置）：重输登录密码通过二次验证后，15 分钟内免验（Redis 记录）。
module Crm::SensitiveSession
  TTL = 15.minutes

  def self.grant(account, user)
    Redis::Alfred.setex(key(account, user), '1', TTL)
  end

  def self.active?(account, user)
    Redis::Alfred.get(key(account, user)).present?
  end

  def self.key(account, user)
    "CRM_SENSITIVE_SESSION::#{account.id}::#{user.id}"
  end
end
