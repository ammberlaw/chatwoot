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
            elsif (params[:library] || params.dig(:category, :library)) == 'GENERAL'
              # 文档中心：传 section_id 则按板块过滤；不传则全部公司文件夹（「全公司文档」视图）
              s = scope.company_scope
              params[:section_id].present? ? s.for_section(params[:section_id]) : s
            else
              scope.company_scope.for_section(scoped_section_id)
            end
    @categories = scope.ordered
  end

  def create
    if personal_request?
      @category = Current.account.crm_knowledge_categories.create!(category_params.merge(user_id: current_user.id))
    else
      return render_forbidden unless company_manageable? || manages_section?(scoped_section_id)

      @category = Current.account.crm_knowledge_categories.create!(category_params.merge(section_id: scoped_section_id))
    end
  end

  def update
    @category.update!(category_params)
    # 同步归属该文件夹的文档冗余分类名（文档按 category_id 认路，此名仅供展示/搜索）。
    Current.account.crm_knowledge_docs.where(category_id: @category.id).update_all(category: @category.name)
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
    manageable = if @category.user_id
                   @category.user_id == current_user.id
                 else
                   company_manageable? || manages_section?(@category.section_id)
                 end
    render_forbidden unless manageable
  end

  def company_manageable?
    Current.account_user.administrator? || Current.account_user.crm_deputy_admin? || Current.account_user.crm_manager?
  end

  # 板块负责人：在自己负责的文档中心板块内可管理文件夹（与前端授权 + 文档控制器保持一致）。
  def manages_section?(section_id)
    section_id.present? && managed_section_ids.include?(section_id.to_i)
  end

  def managed_section_ids
    @managed_section_ids ||= Crm::DocSection.managed_ids_for(Current.account, current_user.id)
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

  # 文档中心（GENERAL 库）分类与个人分类对全员共享（无 CRM 销售数据权限者如人事/纯文档负责人亦可）；
  # 销售资料（SALES 库）公司分类仍受 CRM 门禁，公司分类写权另由 company_manageable?/manages_section? 限管理员/负责人。
  def ensure_crm_access
    return if doc_center_scope?

    super
  end

  # index/新建按请求 library 参数判断；成员操作（update/destroy 不带 library）按目标分类推断。
  def doc_center_scope?
    lib = params[:library].presence || params.dig(:category, :library).presence
    return lib == 'GENERAL' if lib.present?
    return true if params[:view] == 'mine' || personal_request?

    target_general_category?
  end

  # 目标分类是否属文档中心（GENERAL）：个人分类交由归属人判断；公司分类只要不在「销售资料」板块即 GENERAL。
  def target_general_category?
    return false if params[:id].blank?

    cat = Current.account.crm_knowledge_categories.select(:user_id, :section_id).find_by(id: params[:id])
    return false unless cat

    cat.user_id.present? || (cat.section_id.present? && cat.section_id != sales_section_id)
  end

  def check_authorization
    authorize(Crm::KnowledgeCategory)
  end

  def category_params
    params.require(:category).permit(:name, :position, :parent_id)
  end
end
