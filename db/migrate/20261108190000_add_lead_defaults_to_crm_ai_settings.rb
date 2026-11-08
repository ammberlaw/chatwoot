class AddLeadDefaultsToCrmAiSettings < ActiveRecord::Migration[7.1]
  # 公司级默认初筛条件。新建任务时自动带上，业务员可以再改。
  # 不这么做的话，11 个人写 11 套标准，判出来的东西没有可比性，
  # 而初筛条件恰恰是「准不准」的另一半（关键词是前一半）。
  def change
    add_column :crm_ai_settings, :lead_default_criteria, :text
  end
end
