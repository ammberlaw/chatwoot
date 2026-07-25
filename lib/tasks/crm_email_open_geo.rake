# 回填历史邮件打开记录的归属地（city/country 为空且有 IP 的行）。
# 用法：bundle exec rails crm:backfill_email_open_geo
namespace :crm do
  desc 'Backfill city/country for CRM email opens missing geo'
  task backfill_email_open_geo: :environment do
    resolver = Crm::IpGeoResolver.new
    scope = Crm::EmailOpen.where(country: nil, city: nil).where.not(ip_address: nil)
    total = scope.count
    done = 0
    scope.find_each do |open|
      geo = resolver.resolve(open.ip_address)
      open.update!(country: geo[:country], city: geo[:city]) if geo[:country] || geo[:city]
      done += 1
      sleep 0.3 # 尊重 ip-api 免费限速（45 次/分钟）
    end
    puts "[crm:backfill_email_open_geo] 处理 #{done}/#{total} 条"
  end
end
