class Api::V1::NotificationSubscriptionsController < Api::BaseController
  before_action :set_user

  def create
    return unless valid_native_subscription?

    notification_subscription = NotificationSubscriptionBuilder.new(user: @user, params: notification_subscription_params).perform

    render json: notification_subscription
  end

  def destroy
    subscriptions = current_user.notification_subscriptions
    notification_subscription = if params[:subscription_type] == 'native' && params[:device_id].present?
                                  subscriptions.native.find_by(identifier: "native:#{params[:device_id]}")
                                else
                                  subscriptions.where(["subscription_attributes->>'push_token' = ?", params[:push_token]]).first
                                end
    notification_subscription.destroy! if notification_subscription.present?
    head :ok
  end

  def configuration
    render json: Notification::NativePushService.client_config
  end

  private

  def valid_native_subscription?
    subscription = notification_subscription_params
    provider = subscription[:subscription_type]
    return true unless NotificationSubscription::NATIVE_TYPES.include?(provider)

    attrs = subscription[:subscription_attributes] || {}
    platform = provider == 'apns' ? 'ios' : 'android'
    token_valid = attrs[:push_token].to_s.match?(/\A[\x21-\x7E]{8,4096}\z/)
    token_valid &&= attrs[:push_token].to_s.match?(/\A[0-9a-f]{32,512}\z/i) if provider == 'apns'
    unless attrs[:platform] == platform && token_valid &&
           attrs[:device_id].to_s.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i) &&
           attrs[:account_id].to_s.match?(/\A[1-9]\d*\z/)
      render json: { error: '设备推送信息无效，请重新开启通知' }, status: :unprocessable_entity
      return false
    end
    unless current_user.account_users.where(account_id: attrs[:account_id].to_i, deactivated_at: nil).exists?
      render json: { error: '无权为该企业登记消息通知' }, status: :forbidden
      return false
    end
    public_config = Notification::NativePushService.client_config[:providers].fetch(provider.to_sym)
    valid_config = public_config[:enabled] && attrs[:app_id] == public_config[:app_id]
    valid_config &&= public_config[:environments].include?(attrs[:environment]) if provider == 'apns'
    unless valid_config
      render json: { error: '后台消息通知尚未开通，请联系管理员' }, status: :service_unavailable
      return false
    end
    true
  end

  def set_user
    @user = current_user
  end

  def notification_subscription_params
    params.require(:notification_subscription).permit(:subscription_type, subscription_attributes: {})
  end
end
