# MES 生产预警日报：把逾期/临近交期/滞留/短缺推送给相关成员。
class MesAlertMailer < ApplicationMailer
  def daily_digest
    return unless smtp_config_set_or_development?

    @account = params[:account]
    @recipient = params[:recipient]
    @alerts = params[:alerts] || {}
    return if empty?

    mail(to: @recipient,
         subject: "【#{brand_name}】MES 生产预警日报 · #{Time.zone.today.strftime('%Y-%m-%d')}")
  end

  private

  def empty?
    %i[overdue due_soon stalled shortages].all? { |k| Array(@alerts[k]).empty? }
  end

  def brand_name
    GlobalConfig.get('BRAND_NAME', 'INSTALLATION_NAME')['BRAND_NAME'] ||
      GlobalConfig.get('INSTALLATION_NAME')['INSTALLATION_NAME'] || 'Wintouch'
  end
end
