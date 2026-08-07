# PI 卖方预录（单例，按人隔离）：每个业务员维护一份自己的对外落款联系方式。
# show 无预录时回退默认值（CRM 英文名 + 默认邮箱）方便首次填写；update 为 upsert。
class Api::V1::Accounts::Crm::PiSellerProfilesController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization

  def show
    @profile = existing_profile || default_profile
  end

  def update
    @profile = Current.account.crm_pi_seller_profiles.find_or_initialize_by(owner_id: current_user.id)
    @profile.update!(profile_params)
    render :show
  end

  private

  def check_authorization
    authorize(Crm::PiSellerProfile)
  end

  def existing_profile
    Current.account.crm_pi_seller_profiles.owned_by(current_user.id).first
  end

  # 首次未录时的建议值：联系人=CRM英文名(兜底真名)，邮箱=默认收发邮箱。
  def default_profile
    Crm::PiSellerProfile.new(
      account: Current.account,
      owner_id: current_user.id,
      contact_name: current_user.crm_name.presence || current_user.name,
      email: default_mailbox_email
    )
  end

  def default_mailbox_email
    accounts = Current.account.crm_mail_accounts.owned_by(current_user.id)
    accounts.where(is_default: true).limit(1).pick(:email_address) || accounts.limit(1).pick(:email_address)
  end

  def profile_params
    params.require(:pi_seller_profile).permit(:contact_name, :mobile, :email)
  end
end
