# MES 站内通知：仅返回当前用户自己的通知（生产流转/审批/接单待办）。
class Api::V1::Accounts::Mes::NotificationsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_notification, only: [:mark_read]

  def index
    scope = my_notifications
    scope = scope.unread if boolean_param(:unread)
    @unread_count = my_notifications.unread.count
    @notifications = scope.recent_first.page(page_param).per(RESULTS_PER_PAGE)
  end

  # 未读数（用于侧栏角标轮询/兜底）。口径必须和 index 一致，
  # 否则角标说有 6 条、点进去只有 2 条。
  def unread_count
    render json: { payload: { unread_count: my_notifications.unread.count } }
  end

  def mark_read
    @notification.update!(read_at: Time.current) if @notification.read_at.nil?
    head :ok
  end

  def mark_all_read
    my_notifications.unread.update_all(read_at: Time.current, updated_at: Time.current)
    head :ok
  end

  private

  # module=erp 只看财务通知，其余（默认）只看生产通知。ERP 复用同一张表，
  # 不分开的话生产端会被一屏应付逾期淹掉。
  def my_notifications
    Current.account.mes_notifications.for_recipient(current_user.id).for_module(params[:module])
  end

  def fetch_notification
    @notification = Current.account.mes_notifications.for_recipient(current_user.id).find(params[:id])
  end

  def boolean_param(key)
    ActiveModel::Type::Boolean.new.cast(params[key])
  end

  def check_authorization
    authorize(Mes::Notification)
  end
end
