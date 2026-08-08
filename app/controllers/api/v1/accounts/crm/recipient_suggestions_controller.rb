# 写邮件收件人/抄送/密送的输入联想：按输入词模糊匹配「我的客户联系人」+「同事」。
# type 区分来源（contact=客户联系人 / member=同事），前端据此显示不同图标。
class Api::V1::Accounts::Crm::RecipientSuggestionsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization

  MAX = 15

  def index
    q = params[:q].to_s.strip
    return render(json: []) if q.length < 1

    render json: (contact_hits(q) + member_hits(q)).uniq { |h| h[:email].downcase }.first(MAX)
  end

  private

  def check_authorization
    authorize(Crm::Customer)
  end

  # 我的客户（owner=本人）名下、有邮箱的联系人。
  def contact_hits(query)
    like = "%#{query}%"
    Current.account.contacts
           .joins('INNER JOIN crm_customers ON crm_customers.id = contacts.crm_customer_id')
           .where(crm_customers: { account_owner_id: current_user.id })
           .where.not(contacts: { email: [nil, ''] })
           .where('contacts.name ILIKE :q OR contacts.email ILIKE :q', q: like)
           .limit(MAX)
           .map { |c| { name: c.name, email: c.email, type: 'contact' } }
  end

  # 同事（全公司 CRM 成员），按中/英文名或邮箱匹配。
  def member_hits(query)
    like = "%#{query}%"
    Current.account.users
           .where.not(email: [nil, ''])
           .where('users.name ILIKE :q OR users.crm_name ILIKE :q OR users.email ILIKE :q', q: like)
           .limit(MAX)
           .map { |u| { name: u.crm_name.presence || u.name, email: u.email, type: 'member' } }
  end
end
