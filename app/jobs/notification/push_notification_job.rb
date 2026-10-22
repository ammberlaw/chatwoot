class Notification::PushNotificationJob < ApplicationJob
  queue_as :default
  retry_on Notification::NativePushService::DeliveryError, wait: :polynomially_longer, attempts: 5

  def perform(notification)
    Notification::PushNotificationService.new(notification: notification).perform
  end
end
