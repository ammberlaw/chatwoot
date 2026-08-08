class Api::V1::Accounts::Crm::QuickTextsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_quick_text, only: [:update, :destroy]

  # 只列/管自己的快速文本。
  def index
    scope = Current.account.crm_quick_texts.owned_by(current_user.id)
    if params[:q].present?
      term = "%#{params[:q].strip}%"
      scope = scope.where('title ILIKE :t OR body ILIKE :t', t: term)
    end
    @quick_texts = scope.order(updated_at: :desc)
  end

  def create
    @quick_text = Current.account.crm_quick_texts.create!(quick_text_params.merge(owner_id: current_user.id))
    render :show
  end

  def update
    @quick_text.update!(quick_text_params)
    render :show
  end

  def destroy
    @quick_text.destroy!
    head :ok
  end

  private

  def fetch_quick_text
    @quick_text = Current.account.crm_quick_texts.owned_by(current_user.id).find(params[:id])
  end

  def check_authorization
    authorize(Crm::QuickText)
  end

  def quick_text_params
    params.require(:quick_text).permit(:title, :body)
  end
end
