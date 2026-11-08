# 丢弃线索，并记下**为什么**。
#
# 原因不是给人看的记录，是**给 AI 初筛学的方向**——没有原因，系统只能学到
# 「这家不要」，学不到「这类不要」（见 Crm::LeadScreenMemory）。
# 界面上是点菜单选原因，一条条点；在这里一句话能处理一批，判例库才攒得起来。
class Crm::Agent::Tools::DiscardLead < Crm::Agent::Tools::Base
  writes_data

  description '丢弃一条或几条新客开发线索，并记下原因。原因会喂给 AI 初筛，让下一轮少搜到同类。'
  param :lead_ids, desc: '线索ID，多条用逗号隔开，例如「120,133,145」'
  param :reason, desc: "原因码：#{Crm::LeadScreenMemory::DISCARD_REASONS.map { |k, v| "#{k} #{v}" }.join('｜')}"

  def execute(lead_ids:, reason:)
    code = reason.to_s.strip.upcase
    return reason_help unless Crm::LeadScreenMemory::DISCARD_REASONS.key?(code)

    leads = scope.leads.where(id: parse_ids(lead_ids)).where.not(status: 'CLAIMED')
    return '没找到可丢弃的线索（已建档的不能丢）。' if leads.empty?

    names = leads.map(&:company_name).uniq
    leads.find_each { |lead| discard(lead, code) }
    "已丢弃 #{leads.size} 条：#{names.join('、')}。原因记作「#{Crm::LeadScreenMemory::DISCARD_REASONS[code]}」，" \
      '下一轮初筛会按这个方向往严判。'
  end

  private

  def discard(lead, code)
    # 经 agent 丢的同样记人——两条路记法不一致的话，审计表上会凭空少掉一批。
    lead.update!(status: 'DISCARDED', discarded_by_id: scope.user_id, discarded_at: Time.current,
                 raw: lead.raw.merge('discard_reason' => code))
  end

  def parse_ids(value) = value.to_s.scan(/\d+/).map(&:to_i).uniq

  def reason_help
    "原因码不对。只能用：#{Crm::LeadScreenMemory::DISCARD_REASONS.map { |k, v| "#{k}（#{v}）" }.join('、')}"
  end
end
