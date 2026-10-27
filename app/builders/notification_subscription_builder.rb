class NotificationSubscriptionBuilder
  pattr_initialize [:params, :user!]

  def perform
    return build_native_subscription if NotificationSubscription::NATIVE_TYPES.include?(params[:subscription_type])

    # if multiple accounts were used to login in same browser
    move_subscription_to_user if identifier_subscription && identifier_subscription.user_id != user.id
    identifier_subscription.blank? ? build_identifier_subscription : update_identifier_subscription
    identifier_subscription
  end

  private

  def build_native_subscription
    subscription = NotificationSubscription.find_or_initialize_by(identifier: identifier)
    if subscription.persisted?
      subscription.with_lock { subscription.update!(params.merge(user_id: user.id)) }
    else
      subscription.assign_attributes(params.merge(user_id: user.id))
      subscription.save!
    end
    subscription
  rescue ActiveRecord::RecordNotUnique
    # Another registration for this same installation won the unique index.
    retry
  end

  def identifier
    @identifier ||= params[:subscription_attributes][:endpoint] if params[:subscription_type] == 'browser_push'
    @identifier ||= params[:subscription_attributes][:device_id] if params[:subscription_type] == 'fcm'
    if NotificationSubscription::NATIVE_TYPES.include?(params[:subscription_type])
      @identifier ||= "native:#{params[:subscription_attributes][:device_id]}"
    end
    @identifier
  end

  def identifier_subscription
    @identifier_subscription ||= NotificationSubscription.find_by(identifier: identifier)
  end

  def move_subscription_to_user
    @identifier_subscription.update(user_id: user.id)
  end

  def build_identifier_subscription
    @identifier_subscription = user.notification_subscriptions.create!(params.merge(identifier: identifier))
  end

  def update_identifier_subscription
    identifier_subscription.update(params.merge(identifier: identifier))
  end
end
