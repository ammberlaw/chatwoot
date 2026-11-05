# 孤儿审计的手查入口。逻辑在 Crm::OrphanAuditService（与每月定时的
# Crm::OrphanAuditJob 共用一份），这里只负责打印。
namespace :wintouch do
  desc '孤儿审计：没人管的单、无主的配置、离职者遗留'
  task orphans: :environment do
    Account.find_each do |account|
      sections = Crm::OrphanAuditService.new(account).call
      total = sections.sum { |s| s[:rows].size }
      puts "\n#{'=' * 56}\n账号 ##{account.id} #{account.name}：#{total.zero? ? '✅ 没有发现孤儿' : "⚠️ #{total} 项需要处理"}"
      sections.each do |s|
        puts "\n【#{s[:title]}】#{s[:why]}"
        s[:rows].first(12).each { |r| puts "  #{r}" }
        puts "  …共 #{s[:rows].size} 项" if s[:rows].size > 12
      end
    end
  end
end
