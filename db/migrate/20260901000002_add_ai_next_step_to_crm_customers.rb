class AddAiNextStepToCrmCustomers < ActiveRecord::Migration[7.1]
  def change
    # AI「下一步建议」缓存：由收信时的商机进度识别（EmailProgressJob）顺手写入，
    # 客户详情页直接读缓存展示，不在打开页面时实时调用 AI（省 token）。
    add_column :crm_customers, :ai_next_step, :text
    add_column :crm_customers, :ai_next_step_at, :datetime
  end
end
