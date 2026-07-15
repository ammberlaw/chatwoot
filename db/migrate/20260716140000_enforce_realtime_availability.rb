# 在线状态改为系统实时判定：全员强制 auto_offline，并清掉历史手动设置的忙碌/离线状态。
class EnforceRealtimeAvailability < ActiveRecord::Migration[7.1]
  def up
    execute 'UPDATE account_users SET auto_offline = TRUE, availability = 0'
  end

  def down; end
end
