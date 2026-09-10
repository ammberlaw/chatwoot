# 存量邮件里的内联 base64 图落成附件（新收的信已在 Crm::EmailIngestion 里这么处理）。
# 为什么要跑：正文被 base64 图撑到 BODY_MAX_LENGTH 的老邮件，回复时整段引用必然超长，
# 表现为「Body html is too long」发不出去。跑完这些邮件的正文会小一个数量级。
#
#   bundle exec rails crm:inline_images         # 只统计，不写库、不建附件
#   bundle exec rails crm:inline_images[apply]  # 实际转换
namespace :crm do
  task :inline_images, [:mode] => :environment do |_t, args|
    apply = args[:mode] == 'apply'
    scope = Crm::Email.where('body_html LIKE ?', '%data:image%')
    puts "命中 #{scope.count} 封邮件（#{apply ? '实际转换' : '仅统计'}）"

    saved = 0
    scope.find_each do |email|
      before = email.body_html.to_s.length
      if apply
        html, blobs = Crm::MailInlineImages.extract(email.body_html)
        next if blobs.empty?

        blobs.each { |blob| email.files.attach(blob) }
        email.update_columns(body_html: html) # rubocop:disable Rails/SkipsModelValidations
        after = html.length
      else
        after = email.body_html.gsub(Crm::MailInlineImages::DATA_URI_RE, '').length
        next if after == before
      end
      saved += before - after
      puts "  ##{email.id} #{before} → #{after}"
    end
    puts "合计省下 #{(saved / 1024.0).round(1)} KB 正文"
  end

  # 补收某封邮件丢失的附件（收信日志出现「attach failed email=xxx」时用）：
  #   bundle exec rails "crm:repair_attachments[2435]"
  task :repair_attachments, [:email_id] => :environment do |_t, args|
    email = Crm::Email.find(args[:email_id])
    puts "#{email.id} #{email.subject.to_s[0, 40]}｜现有附件 #{email.files.count} 个"
    result = Crm::MailAttachmentRepair.new(email: email).perform
    puts result[:ok] ? "补收 #{result[:added]} 个附件，现共 #{email.files.reload.count} 个" : "失败：#{result[:reason]}"
  end
end
