# == Schema Information
#
# Table name: crm_access_logs
#
#  id            :bigint           not null, primary key
#  action        :string           not null
#  resource_type :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  resource_id   :bigint
#  user_id       :bigint           not null
#
# Indexes
#
#  idx_crm_access_logs_on_resource  (account_id,resource_type,resource_id,created_at)
#

# 敏感数据访问日志：谁在何时查看了员工档案/薪资配置（action: list / view）。
class Crm::AccessLog < ApplicationRecord
  belongs_to :account
  belongs_to :user
end
