class AddApolloSearchLimitsToCrmAiSettings < ActiveRecord::Migration[7.1]
  # 挖客户的配额。
  #
  # 2026-11-10 对账实证：**挖公司是主要成本**，不是我一开始以为的「只有解锁花钱」。
  # 那天 618 credits 里，背调（155 次调用）解释不了大头，挖公司调了 512 次才是真凶。
  # 而业务员不知道点一次「搜索潜在客户」要花钱——两个人各建了选 11~13 个国家的任务，
  # 市场越多 × 关键词越多 = 挖的公司越多 = 烧得越快。
  #
  # 口径按**任务负责人**算：谁建的任务，挖回来的公司算谁的。
  def change
    add_column :crm_ai_settings, :apollo_search_limit, :integer
    add_column :crm_ai_settings, :apollo_search_limits, :jsonb, default: {}, null: false
  end
end
