# 工作月报邮件：每月 1 号把上月经营数据推给各业务员/主管/管理员（各按权限范围）。
# 走平台 SMTP（系统通知邮件，非业务员收发信邮箱）。参数经 sidekiq 序列化，均为纯值。
class Crm::MonthlyReportMailer < ApplicationMailer
  # 自带完整品牌外壳（暖橙），不套共享 mailer/base 布局——否则正文 div 被布局的
  # <table> 触发 HTML 表格寄养重排、且与布局自带卡片/页脚重复。
  layout false

  def monthly_digest
    return unless smtp_config_set_or_development?

    @account = params[:account]
    @recipient_name = params[:recipient_name]
    @report = params[:report] || {}
    @month_label = params[:month_label] # 如「2026 年 7 月」

    mail(to: params[:recipient],
         subject: "【#{brand_name}】#{@month_label} 工作月报已到，请查阅")
  end

  private

  def brand_name
    GlobalConfig.get('BRAND_NAME', 'INSTALLATION_NAME')['BRAND_NAME'] ||
      GlobalConfig.get('INSTALLATION_NAME')['INSTALLATION_NAME'] || 'Wintouch'
  end
  helper_method :brand_name

  # 金额 micros → 千分位两位小数字符串（模板用），如 3,383,789.67。
  def money(micros)
    ActiveSupport::NumberHelper.number_to_delimited(format('%.2f', micros.to_i / 1_000_000.0), delimiter: ',')
  end
  helper_method :money
end
