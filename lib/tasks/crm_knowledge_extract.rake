# 知识库存量补录：把已有文档的附件抽成可搜索正文。
#
#   rake crm:kb:extract            只抽没抽过的（可反复跑，断了接着来）
#   rake crm:kb:extract REDO=1     连抽过的也重抽（换了抽取逻辑时用）
#   rake crm:kb:extract LIMIT=10   先抽几篇看看效果
#   rake crm:kb:stats              看现在抽到什么程度
#
# 不调模型、纯解析，所以可以对全库跑。生产实测 40 份 PDF 抽样 39 份抽得出正文，
# 抽不出的那份是「已转曲」的画册（文字是矢量路径，本来就没有文字层）。
namespace :crm do
  namespace :kb do
    desc '把知识库附件抽成可搜索正文（LIMIT=n 只抽 n 篇，REDO=1 重抽已抽过的）'
    task extract: :environment do
      scope = Crm::KnowledgeDoc.kept.joins(:files_attachments).distinct
      scope = scope.where(extract_state: nil) unless ENV['REDO']
      scope = scope.limit(ENV['LIMIT'].to_i) if ENV['LIMIT'].to_i.positive?

      ids = scope.pluck(:id)
      puts "待抽 #{ids.size} 篇"
      done = Hash.new(0)
      ids.each_with_index do |id, i|
        Crm::KnowledgeExtractJob.perform_now(id)
        doc = Crm::KnowledgeDoc.find_by(id: id)
        done[doc&.extract_state || 'gone'] += 1
        print "\r  #{i + 1}/#{ids.size}  #{done.map { |k, v| "#{k}:#{v}" }.join(' ')}"
      end
      puts
      puts '完成。done=抽到正文 / empty=没有文字层 / skipped=只有视频图片 / failed=解析报错'
    end

    desc '知识库抽取进度'
    task stats: :environment do
      total = Crm::KnowledgeDoc.kept.count
      with_files = Crm::KnowledgeDoc.kept.joins(:files_attachments).distinct.count
      puts "知识库 #{total} 篇，其中带附件 #{with_files} 篇"
      puts
      Crm::KnowledgeDoc.kept.group(:extract_state).count.sort_by { |_, v| -v }.each do |state, n|
        label = { 'done' => '抽到正文', 'empty' => '没有文字层', 'skipped' => '只有视频/图片',
                  'failed' => '解析报错', nil => '还没抽' }[state] || state
        puts format('  %-14s %5d', label, n)
      end
      chars = Crm::KnowledgeDoc.kept.where(extract_state: 'done').sum('LENGTH(extracted_text)')
      puts
      puts "可搜索正文合计 #{ActiveSupport::NumberHelper.number_to_delimited(chars)} 字"
      Crm::KnowledgeDoc.kept.where(extract_state: 'failed').limit(5).each do |d|
        puts "  报错示例：#{d.name} —— #{d.extract_error}"
      end
    end
  end
end
