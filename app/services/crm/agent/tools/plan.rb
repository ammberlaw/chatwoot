# 动手之前先把要做的几步摆出来。
#
# 为什么要有这个：StepRecorder 记的是**事后流水**——每调一次工具摆一行，开跑时
# 根本不知道要几步（它自己的注释里写着）。于是一个「把这三封询价都整理成报价单」
# 的活儿，用户只能看着步骤一条条冒出来，既不知道还剩多少，也看不出它有没有漏掉谁；
# 真漏了一个，要等答完了才发现。
#
# 先列计划就解决这两件事：① 用户一眼看出它理解的任务范围对不对，不对可以当场打断；
# ② 模型自己有了一张清单，不容易做到一半忘了还有第三封。
#
# 计划不是承诺：发现原计划不对（客户其实只有两封信、库存不够改不了）就再调一次
# 本工具把计划改掉——Codex 那套「改计划」正是靠这个显得可靠，而不是硬着头皮走完。
class Crm::Agent::Tools::Plan < Crm::Agent::Tools::Base
  description '动手前先列计划：需要分 3 步以上才能做完的活儿（例如「把这几封询价都整理成报价单」' \
              '「这个客户背调一遍再写封开发信」），先调这个把步骤列出来给用户看，再开始做。' \
              '中途发现计划要改（少了一步、或某步做不了），再调一次本工具把新计划报上来。' \
              '一两步就能答完的问题不要调，列个计划反而碍事。'
  param :steps, desc: '每行一步，2-6 步，用动词开头写清楚做什么（例：1. 查出这三封询价各自的客户）'
  param :done, type: 'integer', desc: '改计划时填：前几步已经做完了。第一次列计划不填', required: false

  MAX_STEPS = 6
  # 行首的「1.」「- 」「①」这些序号符号，模型爱加，列表渲染时会变成双重编号。
  BULLET = /\A\s*[-*•·]?\s*[\d一二三四五六①②③④⑤⑥]*\s*[.、)）:：]?\s*/

  def execute(steps:, done: nil)
    list = parse(steps)
    return '计划是空的。每行写一步，至少两步；一步就能做完的事不用列计划，直接做。' if list.size < 2

    finished = done.to_i.clamp(0, list.size)
    "#{header(list, finished)}\n#{render(list, finished)}\n#{TAIL}"
  end

  private

  TAIL = '计划已经摆到用户面前了。现在按这个顺序做，做完一步接着下一步；' \
         '中途发现哪一步做不了或者漏了一步，再调一次 plan 把计划改掉，别闷头跳过。'.freeze

  def parse(steps)
    steps.to_s.split(/\r?\n/).filter_map { |line| line.sub(BULLET, '').strip.presence }.first(MAX_STEPS)
  end

  def header(list, finished)
    finished.zero? ? "计划（共 #{list.size} 步）：" : "计划已更新（共 #{list.size} 步，前 #{finished} 步已完成）："
  end

  def render(list, finished)
    list.map.with_index(1) { |step, i| "#{i <= finished ? '✓' : '○'} #{i}. #{step}" }.join("\n")
  end
end
