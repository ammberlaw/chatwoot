# CRM 视角的联系人接口：按客户列联系人、维护联系人的 CRM 扩展字段与客户归属。
# 联系人本体 CRUD 走 Chatwoot 原生 contacts API；此处只管 CRM 侧的关联与扩展字段。
class Api::V1::Accounts::Crm::ContactsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_contact, only: [:update]

  # 仅当该客户在当前用户可见范围内才返回其联系人，否则为空（防越权读他人客户联系人）。
  def index
    @contacts = Current.account.contacts
                       .where(crm_customer_id: visible_customers.where(id: params[:customer_id]).select(:id))
                       .order(is_primary_contact: :desc, id: :asc)
  end

  def update
    new_cid = contact_params[:crm_customer_id]
    return render_no_customer_access if new_cid.present? && !visible_customers.exists?(id: new_cid)

    @contact.update!(contact_params)
  end

  private

  def render_no_customer_access
    render json: { error: '无权将联系人归属到该客户' }, status: :forbidden
  end

  # 联系人按 id 直取也收口到可见客户，防止越权改他人客户的联系人（含改归属）。
  def fetch_contact
    @contact = Current.account.contacts
                      .where(crm_customer_id: visible_customers.select(:id)).find(params[:id])
  end

  def check_authorization
    authorize(Crm::Customer)
  end

  def contact_params
    params.require(:contact).permit(
      :crm_customer_id, :whats_app, :wechat, :is_primary_contact, :contact_preference,
      :crm_last_contact_at, :contact_remark, :product_category, :country_region, :customer_group
    )
  end
end
