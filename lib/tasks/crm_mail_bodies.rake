# 补回 2026-09-08 之前被 20000 字上限截断的邮件正文（见 Crm::MailBodyRepair）。
#
#   bundle exec rake 'crm:repair_bodies[10,dry]'   # 试运行：只回查不写库
#   bundle exec rake 'crm:repair_bodies[10]'       # 实修 10 封
#   bundle exec rake 'crm:repair_bodies[0]'        # 实修全部（0 = 不限）
#
# 逐封串行、每封之间停一下：回查要连邮箱服务器，打太急会被限流，也避免把
# 生产内存拉满。跑完按原因分类汇总，捞不回来的一目了然。
namespace :crm do
  desc '按 Message-ID 回查邮箱服务器，补回被截断的邮件正文'
  task :repair_bodies, [:limit, :mode] => :environment do |_t, args|
    limit = args[:limit].to_i
    dry = args[:mode].to_s.start_with?('dry')

    scope = Crm::Email.where("body_html LIKE '%已截断）'").order(email_date: :desc)
    scope = scope.limit(limit) if limit.positive?
    total = scope.count
    puts "#{dry ? '【试运行】' : '【实修】'}待处理 #{total} 封"

    stats = Hash.new(0)
    scope.each_with_index do |email, i|
      r = Crm::MailBodyRepair.new(email: email, dry_run: dry).perform
      key = r.ok ? '成功' : r.reason.sub(/（.*/, '')
      stats[key] += 1
      detail = r.ok ? "#{r.before} → #{r.after} 字，补图 #{r.added_files}" : r.reason
      puts "[#{i + 1}/#{total}] ##{email.id} #{email.subject.to_s[0, 32].ljust(34)} #{detail}"
      sleep 1
    end

    puts "\n—— 汇总 ——"
    stats.sort_by { |_k, v| -v }.each { |k, v| puts "  #{k.ljust(40)} #{v} 封" }
  end
end
