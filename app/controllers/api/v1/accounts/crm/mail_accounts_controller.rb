class Api::V1::Accounts::Crm::MailAccountsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_mail_account, only: [:show, :update, :destroy, :test]

  def index
    @mail_accounts = filtered_accounts.order(:id)
  end

  def show; end

  def create
    @mail_account = Current.account.crm_mail_accounts.create!(
      mail_account_params.merge(owner_id: creatable_owner_id)
    )
  end

  def update
    params_for_update = privileged? ? mail_account_params : mail_account_params.except(:owner_id)
    @mail_account.update!(params_for_update)
  end

  def destroy
    @mail_account.destroy!
    head :ok
  end

  # 实测 SMTP/IMAP 认证，返回是否设置成功 + 失败原因（授权码错等）。
  def test
    render json: Crm::MailAccountVerifier.new(@mail_account).call
  end

  private

  # 数据范围与其余 CRM 数据一致：管理员全部 / 主管团队 / 业务员仅自己配置的邮箱。
  # 越权查看/修改/删除他人邮箱因不在范围内而 404。
  def fetch_mail_account
    @mail_account = scope_by_owner(Current.account.crm_mail_accounts).find(params[:id])
  end

  def check_authorization
    authorize(Crm::MailAccount)
  end

  def filtered_accounts
    scope = scope_by_owner(Current.account.crm_mail_accounts)
    scope = scope.owned_by(current_user.id) if params[:filter] == 'mine'
    scope
  end

  # 管理员/主管可代他人配置邮箱（传 owner_id）；业务员只能给自己配。
  def creatable_owner_id
    return current_user.id unless privileged?

    mail_account_params[:owner_id] || current_user.id
  end

  def privileged?
    Current.account_user.administrator? || Current.account_user.crm_deputy_admin? || Current.account_user.crm_manager?
  end

  def mail_account_params
    params.require(:mail_account).permit(:name, :email_address, :provider, :smtp_host, :smtp_port,
                                         :smtp_user, :smtp_password, :use_ssl, :is_active, :signature, :owner_id,
                                         :imap_enabled, :imap_host, :imap_port, :imap_ssl)
  end
end
