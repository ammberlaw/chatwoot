# 把 WhatsApp Cloud API 的失败响应翻译成消息气泡上能直接看懂的一句话。
#
# https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/#sample-response
#
# 为什么不直接用 error.message：Meta 对账号级封锁（WABA 被停、未绑支付方式、
# 显示名未审批）回的 message 字面就是「An unknown error has occurred.」，真正
# 的线索散在 code / error_subcode / error_data.details / error_user_msg 里。
# 2026-08-29 起出站 15 条全失败、气泡上只写「未知错误」，一个月没人看出根因是
# WABA 未激活（141008）。所以这里把每条线索都拼出来，碰到 Meta 那句没信息量的
# 「unknown」就顺手打一次 health_status 问出真因。
class Whatsapp::CloudErrorMessage
  def self.call(response, channel)
    new(response, channel).call
  end

  def initialize(response, channel)
    @response = response
    @channel = channel
  end

  def call
    return http_error if error.blank?

    Rails.logger.error("[WHATSAPP CLOUD] send failed: #{error.to_json}")

    [detail_with_root_cause.presence, code_suffix].compact_blank.join(' ').presence || http_error
  end

  private

  attr_reader :response, :channel

  def error
    @error ||= response.parsed_response&.dig('error')
  end

  def detail_with_root_cause
    detail = meta_detail
    return detail unless uninformative?(detail)

    [detail, Whatsapp::HealthService.blocking_summary(channel)].compact_blank.join(' · ')
  end

  # Meta 把人话写在三个地方，按「对发件人最有解释力」排序取第一个有值的。
  def meta_detail
    error['error_user_msg'].presence ||
      error.dig('error_data', 'details').presence ||
      error['error_user_title'].presence ||
      error['message'].presence
  end

  # 只有 Meta 自己都说不出所以然时，才值得多花一次 API 调用去问根因。
  def uninformative?(detail)
    return true if detail.blank?

    error['code'].to_i <= 2 || detail.match?(/unknown error|unexpected error/i)
  end

  def code_suffix
    code = error['code'].presence
    return nil if code.blank?

    subcode = error['error_subcode'].presence
    subcode.present? ? "(#{code}/#{subcode})" : "(#{code})"
  end

  # error 块都没有时（网关 502、relay 挂了、HTML 错误页）至少把状态码留下，
  # 别让消息悄悄停在「发送中」。
  def http_error
    "WhatsApp 接口返回 HTTP #{response.code}：#{response.body.to_s.truncate(200)}"
  end
end
