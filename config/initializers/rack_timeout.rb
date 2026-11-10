require 'rack-timeout'

# Reduce noise by filtering state=ready and state=completed which are logged at INFO level
Rails.application.config.after_initialize do
  Rack::Timeout::Logger.level = Logger::ERROR
end

# AI 接口单独放宽请求时限。
#
# 全局 15 秒是给普通接口兜底的（防止慢查询把 puma 线程占死），但 PI 识别、翻译、写信这些要等
# 第三方大模型吐完整段结果，20~40 秒是常态，必然撞墙。更糟的是 rack-timeout 抛的
# RequestTimeoutException 继承自 Exception 而不是 StandardError，控制器里的 rescue 接不住，
# 用户看到的是裸的 500「Internal Server Error」，连「识别失败请重试」都显示不出来。
#
# 只给这几条已知要等模型的路径放宽，其余接口的 15 秒闸刀不动。
# 实例变量会被多个 puma 线程共享，所以当前请求的路径存在线程局部变量里。
#
# ⚠️ 加新的 AI 接口时必须同步加到这里，否则就是 2026-10-15 考核表「AI 建议分」那次：
# 功能本身没问题，纯粹被 15 秒闸刀掐断，用户看到的是裸 500「Internal Server Error」。
# 为此末尾留了 ai_* 的通配，新加的 `post :ai_xxx` 类接口自动吃到放宽，不用再想起这个文件。
module RackTimeoutAiPaths
  AI_PATHS = Regexp.union(
    %r{/crm/pis/parse_pi\z},
    %r{/crm/sales_orders/parse_pi\z},
    %r{/crm/customers/\d+/parse_attachment\z},
    %r{/crm/ai/},
    # 考核表 AI 建议分：6~7 个指标各要一段评分理由，模型稳定跑几十秒。
    %r{/crm/kpi_sheets/\d+/ai_suggest\z},
    # 客户消息里的「翻译这条」，也是等模型吐完才返回。
    %r{/crm/conversation_translation/\d+/translate\z},
    # 展会邀约撰写。
    %r{/crm/exhibition_invites/compose\z},
    %r{/crm/exhibitions/\d+/invites/compose\z},
    # 拓客任务的客户画像：一个市场要出十个本地化关键词，市场越多越慢。
    # 实测 4~5 个市场 8 秒、13 个市场 16 秒——正好跨过 15 秒的默认闸，
    # 用户看到的是「Internal Server Error」，而画像其实在后台跑完了
    # （2026-11-10 肖天海建「欧洲及加拿大医疗一体机」选了 13 个市场）。
    %r{/crm/lead_campaigns/\d+/build_profile\z},
    # 兜底：CRM 下任何 ai_xxx 动作都按 AI 接口放宽。
    %r{/crm/.*\bai_[a-z_]+\z}
  ).freeze
  AI_SERVICE_TIMEOUT = ENV.fetch('RACK_TIMEOUT_AI_SERVICE_TIMEOUT', 90).to_i

  def call(env)
    Thread.current[:rack_timeout_path] = env['PATH_INFO']
    super
  ensure
    Thread.current[:rack_timeout_path] = nil
  end

  def service_timeout
    path = Thread.current[:rack_timeout_path]
    return AI_SERVICE_TIMEOUT if path.present? && AI_PATHS.match?(path)

    super
  end
end

Rack::Timeout.prepend(RackTimeoutAiPaths)
