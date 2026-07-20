# 资料分类：view=mine 返回/创建当前用户的个人分类（人人可管自己的）；
# 否则为公司分类，增删改仅限超级管理员/管理员/部门负责人。
class Api::V1::Accounts::Crm::KnowledgeCategoriesController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_category, only: [:update, :destroy]
  before_action :ensure_manageable, only: [:update, :destroy]

  def index
    scope = Current.account.crm_knowledge_categories
    scope = if params[:view] == 'mine'
              scope.personal_of(current_user.id)
            else
              scope.company_scope.for_section(scoped_section_id)
            end
    @categories = scope.ordered
  end

  def create
    if personal_request?
      @category = Current.account.crm_knowledge_categories.create!(category_params.merge(user_id: current_user.id))
    else
      return render_forbidden unless company_manageable?

      @category = Current.account.crm_knowledge_categories.create!(category_params.merge(section_id: scoped_section_id))
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

  # 分类隔离到的板块：index 经 query 顶层传参，create 经 category 内层传参，两处都兼容。
  # 销售资料库(SALES)映射到「销售资料」板块（其公司文档即归此板块）；文档中心(GENERAL)取当前板块，聚合视图为空。
  def scoped_section_id
    return @scoped_section_id if defined?(@scoped_section_id)

    library = params[:library] || params.dig(:category, :library)
    section = params[:section_id] || params.dig(:category, :section_id)
    @scoped_section_id = library == 'SALES' ? sales_section_id : section.presence
  end

  def sales_section_id
    @sales_section_id ||= Current.account.crm_doc_sections.find_by(name: '销售资料')&.id
  end

  def render_forbidden
    render json: { error: '公司分类仅超级管理员、管理员或部门负责人可管理' }, status: :forbidden
  end

  # 文档中心（GENERAL 库）分类与个人分类对全员共享（无 CRM 销售数据权限者如人事亦可）；
  # 销售资料（SALES 库）公司分类仍受 CRM 门禁，公司分类写权另由 company_manageable? 限管理员/负责人。
  def ensure_crm_access
    lib = params[:library] || params.dig(:category, :library)
    return if lib == 'GENERAL'
    return if params[:view] == 'mine' || personal_request?

    super
  end

  def check_authorization
    authorize(Crm::KnowledgeCategory)
  end

  def category_params
    params.require(:category).permit(:name, :position)
  end
end
