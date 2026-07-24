# 个性签名库（复数资源）：与邮箱解耦，一人可建多条命名签名，写邮件时下拉插入、可设默认。
# 按人隔离：每人只看/管自己的签名（含管理员/主账号），与发信邮箱一致。
class Api::V1::Accounts::Crm::EmailSignaturesController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_signature, only: [:show, :update, :destroy]

  def index
    @signatures = Current.account.crm_email_signatures.owned_by(current_user.id).order(:id)
  end

  def show; end

  def create
    @signature = Current.account.crm_email_signatures.create!(
      signature_params.merge(owner_id: current_user.id)
    )
  end

  def update
    @signature.update!(signature_params)
  end

  def destroy
    @signature.destroy!
    head :ok
  end

  private

  def fetch_signature
    @signature = Current.account.crm_email_signatures.owned_by(current_user.id).find(params[:id])
  end

  def check_authorization
    authorize(Crm::EmailSignature)
  end

  def signature_params
    params.require(:email_signature).permit(:name, :body, :body_html, :is_default)
  end
end
