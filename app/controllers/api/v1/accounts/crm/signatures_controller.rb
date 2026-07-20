# 我的个人签名（单数资源）：成员管理自己在本账号的手写签名图，供 KPI 电子签一键盖章。
# 纯个人资料，不涉 CRM 销售数据，故跳过 CRM 门禁 —— 含人事等无 CRM 数据权限者也可管理自己的签名。
class Api::V1::Accounts::Crm::SignaturesController < Api::V1::Accounts::Crm::BaseController
  skip_before_action :ensure_crm_access
  before_action :fetch_signature

  def show; end

  def create
    return render json: { error: '请上传签名图片' }, status: :unprocessable_entity if params[:image].blank?

    @signature.image.attach(params[:image])
    @signature.save!
    render :show
  end

  def destroy
    return head :ok unless @signature.persisted?

    @signature.image.purge
    @signature.destroy!
    head :ok
  end

  private

  def fetch_signature
    @signature = Current.account.crm_signatures.find_or_initialize_by(user_id: current_user.id)
  end
end
