# 删掉一条记住的事。
#
# 有记就得有删：记错了、或者习惯变了，没地方撤销的话用户只能眼睁睁看它一直错下去。
class Crm::Agent::Tools::Forget < Crm::Agent::Tools::Base
  description '删掉之前记住的某条偏好。用户说「别记这个了」「忘掉…」时用。' \
              '不给关键词就把当前记住的都列出来让他挑。'
  param :keyword, desc: '要删的那条里的关键词；不传则只列出全部记忆不删', required: false

  def execute(keyword: nil)
    rows = Crm::AgentMemory.for_user(scope.account.id, scope.user_id).to_a
    return '目前没有记住任何偏好。' if rows.empty?

    kw = keyword.to_s.strip
    return "目前记住这些：\n#{rows.map { |r| "· #{r.content}" }.join("\n")}\n要删哪条？说个关键词。" if kw.blank?

    hit = rows.select { |r| r.content.include?(kw) }
    return "没有包含「#{kw}」的记忆。现有：\n#{rows.map { |r| "· #{r.content}" }.join("\n")}" if hit.empty?

    hit.each(&:destroy)
    "已忘掉 #{hit.size} 条：#{hit.map(&:content).join('；')}"
  end
end
