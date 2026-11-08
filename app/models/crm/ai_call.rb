# 一次 AI 调用的流水。
#
# 为什么要记：初筛、背调、简报、写信都在烧 token，而在这之前一次都没记过——
# 「这个功能放开给十个人用会花多少钱」只能靠猜。
#
# 只记用量不记金额：单价随模型和供应商变，折算成钱会很快过期；
# token 数是硬事实，要算钱乘一下当时的单价即可。
# == Schema Information
#
# Table name: crm_ai_calls
#
#  id            :bigint           not null, primary key
#  duration_ms   :integer
#  input_tokens  :integer          default(0), not null
#  model         :string
#  output_tokens :integer          default(0), not null
#  purpose       :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  user_id       :bigint
#
# Indexes
#
#  index_crm_ai_calls_on_account_id_and_created_at  (account_id,created_at)
#  index_crm_ai_calls_on_account_id_and_purpose     (account_id,purpose)
#
class Crm::AiCall < ApplicationRecord
  self.table_name = 'crm_ai_calls'

  belongs_to :account
  belongs_to :user, optional: true

  # 这个月按用途汇总：{ 用途 => { calls:, input:, output: } }
  def self.month_summary(account, since: Time.current.beginning_of_month)
    where(account_id: account.id, created_at: since..)
      .group(:purpose)
      .pluck(Arel.sql('purpose, COUNT(*), SUM(input_tokens), SUM(output_tokens), AVG(duration_ms)'))
      .to_h do |purpose, calls, input, output, ms|
        [purpose, { calls: calls, input: input.to_i, output: output.to_i, avg_ms: ms.to_i }]
      end
  end
end
