# 资料分类：view=mine 返回/创建当前用户的个人分类（人人可管自己的）；
# 否则为公司分类，增删改仅限超级管理员/管理员/部门负责人。
class Api::V1::Accounts::Crm::KnowledgeCategoriesController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_category, only: [:update, :destroy]
  before_action :ensure_manageable, only: [:update, :destroy]

  def index
    scope = Current.account.crm_knowledge_categories
    scope = params[:view] == 'mine' ? scope.personal_of(current_user.id) : scope.company_scope
    @categories = scope.ordered
  end

  def create
    if personal_request?
      @category = Current.account.crm_knowledge_categories.create!(category_params.merge(user_id: current_user.id))
    else
      return render_forbidden unless company_manageable?

      @category = Current.account.crm_knowledge_categories.create!(category_params)
    end
  end

  def update
    @category.update!(category_params)
  end

  def destroy
    @category.destroy!
    head :ok
  end

  private

  def fetch_category
    @category = Current.account.crm_knowledge_categories.find(params[:id])
  end

  def ensure_manageable
    manageable = @category.user_id ? @category.user_id == current_user.id : company_manageable?
    render_forbidden unless manageable
  end

  def company_manageable?
    Current.account_user.administrator? || Current.account_user.crm_deputy_admin? || Current.account_user.crm_manager?
  end

  def personal_request?
    params.dig(:category, :personal).to_s == 'true'
  end

  def render_forbidden
    render json: { error: '公司分类仅超级管理员、管理员或部门负责人可管理' }, status: :forbidden
  end

  def check_authorization
    authorize(Crm::KnowledgeCategory)
  end

  def category_params
    params.require(:category).permit(:name, :position)
  end
end
