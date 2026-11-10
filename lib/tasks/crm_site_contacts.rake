# 给存量线索补官网业务邮箱。不花 Apollo credits（只抓官网 + 正则），
# 慢慢排进 deferred 队列，不影响收信和 WhatsApp。
#
# 用法：
#   bundle exec rake crm:site_contacts            # 全部还没有邮箱的
#   bundle exec rake crm:site_contacts MIN_SCORE=50   # 只补够分数的（推荐，省时间）
namespace :crm do
  task site_contacts: :environment do
    scope = Crm::Lead.where.not(domain: nil).where("raw->'bg'->>'emails' IS NULL")
    min = ENV['MIN_SCORE'].presence
    scope = scope.where("(raw->>'screen_score')::int >= ?", min.to_i) if min
    # 一家公司只排一次——同名的那几条由 job 自己盖过去。
    ids = scope.select('DISTINCT ON (company_name) id').order(:company_name, :id).map(&:id)
    ids.each { |id| Crm::LeadSiteContactJob.perform_later(id) }
    puts "已排队 #{ids.size} 家公司（deferred 队列，每家约 3~8 秒）"
  end
end
