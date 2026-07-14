# CRM 视角的联系人接口：按客户列联系人、维护联系人的 CRM 扩展字段与客户归属。
# 联系人本体 CRUD 走 Chatwoot 原生 contacts API；此处只管 CRM 侧的关联与扩展字段。
class Api::V1::Accounts::Crm::ContactsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_contact, only: [:update]

  def index
    @contacts = Current.account.contacts.where(crm_customer_id: params[:customer_id]).order(is_primary_contact: :desc, id: :asc)
  end

  def update
    @contact.update!(contact_params)
  end

  private

  def fetch_contact
    @contact = Current.account.contacts.find(params[:id])
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
