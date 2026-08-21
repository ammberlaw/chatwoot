# 邮件标签定义的管理（增删改查）。标签在邮件上的归属存于 crm_emails.label_ids 数组列，
# 打/去标签走 emails#update（permit label_ids）。授权复用 Crm::Email 策略（同为邮件子功能）。
class Api::V1::Accounts::Crm::EmailLabelsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_label, only: [:update, :destroy]

  def index
    Crm::EmailLabel.seed_defaults!(Current.account)
    render json: { payload: Current.account.crm_email_labels.ordered.map { |l| label_json(l) } }
  end

  def create
    label = Current.account.crm_email_labels.create!(label_params)
    render json: label_json(label)
  end

  def update
    @label.update!(label_params)
    render json: label_json(@label)
  end

  # 删除标签定义时，把该标签 id 从所有邮件的 label_ids 里移除，避免悬挂引用。
  def destroy
    id = @label.id
    @label.destroy!
    Current.account.crm_emails.where('label_ids @> ARRAY[?]::bigint[]', id)
           .update_all(['label_ids = array_remove(label_ids, ?), updated_at = now()', id])
    head :ok
  end

  private

  def fetch_label
    @label = Current.account.crm_email_labels.find(params[:id])
  end

  def check_authorization
    authorize(Crm::Email)
  end

  def label_json(label)
    { id: label.id, name: label.name, color: label.color, position: label.position }
  end

  def label_params
    params.require(:label).permit(:name, :color, :position)
  end
end
