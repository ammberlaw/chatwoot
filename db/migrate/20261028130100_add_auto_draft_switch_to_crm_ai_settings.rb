# 自动预写回复的总开关。默认关——要花模型钱，先让管理员小范围试了再全开。
# 和「新询盘初筛」同一个口径（那个也是默认关的）。
class AddAutoDraftSwitchToCrmAiSettings < ActiveRecord::Migration[7.1]
  def change
    change_table :crm_ai_settings, bulk: true do |t|
      t.boolean :auto_draft_reply_enabled, default: false, null: false
      # 只给名单里的人预写。空＝对所有开了 AI 助手的人生效。
      # 试点期间只填一两个人，别一上来就全公司每天几百次调用。
      t.bigint :auto_draft_user_ids, array: true, default: [], null: false
    end
  end
end
