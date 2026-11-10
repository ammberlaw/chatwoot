# 解锁一条线索的真实联系方式。**这一步才扣 Apollo credits**，所以只在人点了之后才跑。
class Crm::LeadUnlock
  # user 是点解锁的人。记下来才算得出各人本月用了多少额度（见 Crm::ApolloQuota），
  # 也才查得出积分花在哪了。
  def self.call(lead, user = nil)
    return false if lead.apollo_person_id.blank? || lead.status == 'CLAIMED'

    fields = Crm::ApolloClient.new(account: lead.account, scene: 'unlock', user: user).unlock_person(lead.apollo_person_id)
    return false if fields.blank? || fields[:email].blank?

    lead.update!(unlocked_attrs(lead, fields).merge(unlocked_by_id: user&.id, unlocked_at: Time.current))
    true
  # 额度耗尽往上抛，由控制器原样告诉业务员。咽在这里返回 false 的话，
  # 页面只会说「没解锁到邮箱」，人会换一条再点——全公司余额为 0，换几百条都一样。
  rescue Crm::ApolloClient::CreditsExhausted
    raise
  rescue StandardError => e
    Rails.logger.warn("[LeadUnlock] lead=#{lead.id}: #{e.class} #{e.message}")
    false
  end

  # 解锁回来的字段覆盖原来的预览值（名字从「Ma***a」变成真名）；
  # 回来是空的那几项保留原值，别把已有信息抹掉。
  def self.unlocked_attrs(lead, fields)
    {
      status: 'UNLOCKED',
      person_name: fields[:name].presence || lead.person_name,
      title: fields[:title].presence || lead.title,
      email: fields[:email], email_status: fields[:email_status],
      linkedin_url: fields[:linkedin_url],
      domain: lead.domain.presence || fields[:domain]
    }
  end
end
