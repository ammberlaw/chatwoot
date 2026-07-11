class Api::V1::Accounts::Crm::MailAccountsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_mail_account, only: [:show, :update, :destroy]

  def index
    @mail_accounts = filtered_accounts.order(:id)
  end

  def show; end

  def create
    @mail_account = Current.account.crm_mail_accounts.create!(
      mail_account_params.merge(owner_id: mail_account_params[:owner_id] || current_user.id)
    )
  end

  def update
    @mail_account.update!(mail_account_params)
  end

  def destroy
    @mail_account.destroy!
    head :ok
  end

  private

  def fetch_mail_account
    @mail_account = Current.account.crm_mail_accounts.find(params[:id])
  end

  def check_authorization
    authorize(Crm::MailAccount)
  end

  def filtered_accounts
    scope = Current.account.crm_mail_accounts
    scope = scope.owned_by(current_user.id) if params[:filter] == 'mine'
    scope
  end

  def mail_account_params
    params.require(:mail_account).permit(:name, :email_address, :provider, :smtp_host, :smtp_port,
                                         :smtp_user, :smtp_password, :use_ssl, :is_active, :signature, :owner_id)
  end
end
