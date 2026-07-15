class Api::V1::Accounts::Crm::KnowledgeDocsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_doc, only: [:show, :update, :destroy, :attach, :detach, :audits]
  before_action :ensure_doc_manageable, only: [:update, :destroy, :attach, :detach]

  RESULTS_PER_PAGE = 20

  def index
    @docs_scope = filtered_docs
    @docs_count = @docs_scope.count
    @docs = @docs_scope.order(updated_at: :desc).page(params[:page] || 1).per(per_page)
  end

  def show; end

  # 个人文档任何人可建（归属自己）；公司文档需相应管理权（见 company_docs_manageable?）。
  def create
    attrs = doc_params
    return render_forbidden if attrs[:scope] == 'COMPANY' && !company_docs_manageable?(attrs[:library].presence || 'SALES')

    @doc = Current.account.crm_knowledge_docs.create!(attrs.merge(owner_id: current_user.id, scope: attrs[:scope].presence || 'PERSONAL'))
  end

  def update
    @doc.update!(update_params)
  end

  def destroy
    @doc.destroy!
    head :ok
  end

  # 附件上传（追加，不覆盖已有）
  def attach
    @doc.files.attach(params[:files])
    render 'api/v1/accounts/crm/knowledge_docs/show'
  end

  # 删除单个附件
  def detach
    @doc.files.find(params[:attachment_id]).purge
    render 'api/v1/accounts/crm/knowledge_docs/show'
  end

  # 时间轴：文档的创建/编辑历史。
  def audits
    rows = @doc.audits.order(created_at: :desc).limit(80).map do |audit|
      {
        id: audit.id,
        action: audit.action,
        changed_fields: audit.audited_changes.keys,
        user_name: audit.user&.name || audit.username || '系统',
        created_at: audit.created_at
      }
    end
    render json: { payload: rows }
  end

  private

  # 个人文档账号间严格隔离：任何人（含管理员）只能看到公司文档 + 自己的个人文档。
  def visible_docs
    base = Current.account.crm_knowledge_docs
    base.company_docs.or(base.personal_of(current_user.id))
  end

  def fetch_doc
    @doc = visible_docs.find(params[:id])
    # 板块部门可见性：不可见板块内的文档按不存在处理。
    raise ActiveRecord::RecordNotFound if @doc.section_id.present? && !section_visible?(@doc.section_id)
  end

  def section_visible?(section_id)
    return true if company_docs_manageable?('GENERAL')

    visible_section_ids.include?(section_id)
  end

  def visible_section_ids
    @visible_section_ids ||= Crm::DocSection.visible_ids_for(Current.account, current_user.id)
  end

  def check_authorization
    authorize(Crm::KnowledgeDoc)
  end

  # 编辑/删除/附件权限：个人文档仅归属人；公司文档按库分——
  # 销售资料(SALES)=管理员/主管；文档中心(GENERAL)=管理员/指定负责人。
  def ensure_doc_manageable
    return if doc_manageable?(@doc)

    render_forbidden
  end

  def doc_manageable?(doc)
    return doc.owner_id == current_user.id if doc.scope == 'PERSONAL'

    company_docs_manageable?(doc.library)
  end

  def company_docs_manageable?(library)
    return true if Current.account_user.administrator?
    return Crm::DocCenterSetting.for_account(Current.account).owner_id == current_user.id if library == 'GENERAL'

    Current.account_user.crm_manager?
  end

  def render_forbidden
    render json: { error: I18n.t('errors.crm.no_access', default: '无权限执行该操作') }, status: :forbidden
  end

  # 视图：公司文档 / 我的知识库 / 文档看板按分类。
  def filtered_docs
    scope = section_scoped(visible_docs)
    scope = scope.company_docs if params[:filter] == 'company'
    scope = scope.personal_of(current_user.id) if params[:filter] == 'mine'
    search_and_category(scope)
  end

  # 资料库隔离 + 文档中心板块部门可见性（无板块的旧文档全员可见）+ 板块筛选。
  def section_scoped(scope)
    scope = scope.in_library(params[:library]) if params[:library].present?
    scope = scope.where(section_id: [nil] + visible_section_ids) if params[:library] == 'GENERAL' && !company_docs_manageable?('GENERAL')
    scope = scope.where(section_id: params[:section_id]) if params[:section_id].present?
    scope
  end

  def search_and_category(scope)
    scope = scope.where(category: params[:category]) if params[:category].present?
    scope = scope.where('name ILIKE :q OR summary ILIKE :q', q: "%#{params[:q]}%") if params[:q].present?
    scope
  end

  def doc_params
    params.require(:doc).permit(:name, :category, :summary, :scope, :library, :section_id, :body, files: [])
  end

  # 编辑时个人文档不可自行升级为公司文档（越权发布）；有公司文档管理权的可调整范围。
  def update_params
    return doc_params if company_docs_manageable?(@doc.library)

    doc_params.except(:scope, :library)
  end

  # 看板视图一次拉全（上限 200）；未传时回落默认页大小。
  def per_page
    [(params[:per_page].presence || RESULTS_PER_PAGE).to_i, 200].min
  end
end
