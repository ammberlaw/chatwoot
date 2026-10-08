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
module RackTimeoutAiPaths
  AI_PATHS = Regexp.union(
    %r{/crm/pis/parse_pi\z},
    %r{/crm/sales_orders/parse_pi\z},
    %r{/crm/customers/\d+/parse_attachment\z},
    %r{/crm/ai/}
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
