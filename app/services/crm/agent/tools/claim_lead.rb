# 把线索建成客户档案。
#
# 这一步是新客开发和整个 CRM 的接口：建完它就是普通客户，写开发信、建商机、
# 发报价全都能接着做（agent 自己就有 draft_email / create_opportunity）。
# 所以这个工具的返回里**必须带客户 ID**——下一句「给他写封开发信」要靠它。
#
# 撞到已有客户不重复建，直接指过去（口径同建档页查重，见 Crm::LeadToCustomer）。
class Crm::Agent::Tools::ClaimLead < Crm::Agent::Tools::Base
  writes_data

  description '把新客开发的线索建成客户档案。建完就是正式客户，可以接着写开发信、建商机。'
  param :lead_id, type: 'integer', desc: '线索ID（线索池里每行开头那个）'

  def execute(lead_id:)
    lead = scope.leads.find_by(id: lead_id)
    return "看不到 ID #{lead_id} 这条线索。" if lead.nil?
    return "#{lead.company_name} 已经建过档了（客户 ID #{lead.crm_customer_id}）。" if lead.status == 'CLAIMED'

    result = Crm::LeadToCustomer.call(lead, scope.user_id)
    customer = result.customer
    scope.record_artifact(kind: 'customer', id: customer.id, customer_id: customer.id,
                          label: "客户：#{customer.name.truncate(20)}")
    done_text(lead, customer, result.duplicate)
  end

  private

  def done_text(lead, customer, duplicate)
    head = if duplicate
             "#{lead.company_name} 早就在库里了（客户 ID #{customer.id}「#{customer.name}」），没有重复建，这条线索已指过去。"
           else
             "已把 #{lead.company_name} 建成客户（ID #{customer.id}），打了「新客开发」标签。"
           end
    "#{head}#{mail_hint(lead)}"
  end

  # 邮箱没解锁就直说，别让模型接着去写一封发不出去的开发信。
  def mail_hint(lead)
    return '' if lead.email.present?

    '⚠️ 这家的联系人邮箱还没解锁（解锁要花 Apollo 积分，得在新客开发页面上点），' \
      '现在写开发信也发不出去。'
  end
end
