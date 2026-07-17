class Api::V1::Accounts::Crm::KnowledgeDocsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_doc, only: [:show, :update, :destroy, :attach, :detach, :audits]
  before_action :ensure_doc_manageable, only: [:update, :destroy, :attach, :detach]
  before_action :ensure_admin, only: [:recycle_bin, :restore, :purge, :purge_all]
  before_action :fetch_discarded_doc, only: [:restore, :purge]

  RESULTS_PER_PAGE = 20

  def index
    @docs_scope = filtered_docs
    @docs_count = @docs_scope.count
    @docs = @docs_scope.order(updated_at: :desc).page(params[:page] || 1).per(per_page)
  end

  def show; end

  # 个人文档任何人可建（归属自己）；公司文档需相应创建权（见 company_docs_creatable?）。
  def create
    attrs = doc_params
    return render_forbidden if attrs[:scope] == 'COMPANY' && !company_docs_creatable?(attrs[:library].presence || 'SALES')

    @doc = Current.account.crm_knowledge_docs.create!(
      sync_sales_section(attrs).merge(owner_id: current_user.id, scope: attrs[:scope].presence || 'PERSONAL')
    )
  end

  def update
    @doc.update!(update_params)
  end

  # 删除=移入回收站（软删除）；彻底删除由超级管理员/管理员在回收站执行。
  def destroy
    @doc.discard!(current_user.id)
    head :ok
  end

  # ── 回收站（超级管理员与管理员）──
  def recycle_bin
    @docs = Current.account.crm_knowledge_docs.discarded
                   .includes(:owner, :discarded_by)
                   .order(discarded_at: :desc)
  end

  def restore
    @doc.restore!
    head :ok
  end

  def purge
    @doc.destroy!
    head :ok
  end

  def purge_all
    Current.account.crm_knowledge_docs.discarded.destroy_all
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

  # 个人文档账号间严格隔离：任何人（含管理员）只能看到公司文档 + 自己的个人文档。回收站的不在列。
  def visible_docs
    base = Current.account.crm_knowledge_docs.kept
    base.company_docs.or(base.personal_of(current_user.id))
  end

  def fetch_doc
    @doc = visible_docs.find(params[:id])
    # 板块部门可见性：不可见板块内的文档按不存在处理。
    # 仅限 GENERAL 库——SALES 公司资料（与销售资料板块同步共享）在 CRM 侧全员可读。
    raise ActiveRecord::RecordNotFound if @doc.library == 'GENERAL' && @doc.section_id.present? && !section_visible?(@doc.section_id)
  end

  def fetch_discarded_doc
    @doc = Current.account.crm_knowledge_docs.discarded.find(params[:id])
  end

  def ensure_admin
    return if admin_like?

    render_forbidden
  end

  def section_visible?(section_id)
    return true if admin_like?

    visible_section_ids.include?(section_id)
  end

  def visible_section_ids
    @visible_section_ids ||= Crm::DocSection.visible_ids_for(Current.account, current_user.id)
  end

  def check_authorization
    authorize(Crm::KnowledgeDoc)
  end

  # 编辑/删除/附件权限：个人文档仅归属人；文档中心（GENERAL）公司文档=超管/管理员+该文档负责人（可多人）；
  # 销售资料（SALES）公司文档=超管/管理员/部门负责人；其他成员只能浏览下载。
  def ensure_doc_manageable
    return if doc_manageable?(@doc)

    render_forbidden
  end

  def doc_manageable?(doc)
    return doc.owner_id == current_user.id if doc.scope == 'PERSONAL'
    return true if admin_like?

    if doc.library == 'GENERAL'
      doc.manager_ids.include?(current_user.id)
    else
      Current.account_user.crm_manager?
    end
  end

  # 新建公司文档：GENERAL 仅超管/管理员（负责人管既有文档）；SALES 另放开部门负责人。
  def company_docs_creatable?(library)
    return true if admin_like?

    library != 'GENERAL' && Current.account_user.crm_manager?
  end

  def admin_like?
    Current.account_user.administrator? || Current.account_user.crm_deputy_admin?
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

  # 资料库隔离 + 文档中心板块部门可见性（无板块的旧文档全员可见；管理员/副管理员/负责人不受限）+ 板块筛选。
  # CRM「公司资料」与文档中心「销售资料」板块同步共享：文档中心视图并入 SALES 公司文档。
  def section_scoped(scope)
    if params[:library] == 'GENERAL'
      scope = scope.where(library: 'GENERAL').or(scope.where(library: 'SALES', scope: 'COMPANY'))
      scope = scope.where(section_id: [nil] + visible_section_ids) unless admin_like?
    elsif params[:library].present?
      scope = scope.in_library(params[:library])
    end
    scope = scope.where(section_id: params[:section_id]) if params[:section_id].present?
    scope
  end

  # 同步共享的落库口径：SALES 公司文档自动归入「销售资料」板块；
  # 在文档中心「销售资料」板块新建的文档落 SALES 库（CRM 公司资料同步可见）。
  def sync_sales_section(attrs)
    return attrs unless attrs[:scope] == 'COMPANY' && sales_section_id

    case [attrs[:library].presence || 'SALES', attrs[:section_id].to_i == sales_section_id]
    in ['GENERAL', true] then attrs.merge(library: 'SALES')
    in ['SALES', _] then attrs.merge(section_id: attrs[:section_id].presence || sales_section_id)
    else attrs
    end
  end

  def sales_section_id
    return @sales_section_id if defined?(@sales_section_id)

    @sales_section_id = Current.account.crm_doc_sections.find_by(name: '销售资料')&.id
  end

  def search_and_category(scope)
    scope = scope.where(category: params[:category]) if params[:category].present?
    scope = scope.where('name ILIKE :q OR summary ILIKE :q', q: "%#{params[:q]}%") if params[:q].present?
    scope
  end

  def doc_params
    attrs = params.require(:doc).permit(:name, :category, :summary, :scope, :library, :section_id, :body, files: [], manager_ids: [])
    # 文档负责人仅超管/管理员可指定；名单过滤为本账号成员。
    if attrs.key?(:manager_ids)
      if admin_like?
        ids = Array(attrs[:manager_ids]).map(&:to_i).uniq
        attrs[:manager_ids] = Current.account.account_users.where(user_id: ids).pluck(:user_id)
      else
        attrs = attrs.except(:manager_ids)
      end
    end
    attrs
  end

  # 编辑时个人文档不可自行升级为公司文档（越权发布）；公司文档（已过 ensure_doc_manageable）可调整范围。
  def update_params
    return doc_params if @doc.scope == 'COMPANY'

    doc_params.except(:scope, :library)
  end

  # 看板视图一次拉全（上限 200）；未传时回落默认页大小。
  def per_page
    [(params[:per_page].presence || RESULTS_PER_PAGE).to_i, 200].min
  end
end
