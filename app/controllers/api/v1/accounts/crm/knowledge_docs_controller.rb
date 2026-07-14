class Api::V1::Accounts::Crm::KnowledgeDocsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_doc, only: [:show, :update, :destroy, :attach, :detach, :audits]

  RESULTS_PER_PAGE = 20

  def index
    @docs_scope = filtered_docs
    @docs_count = @docs_scope.count
    @docs = @docs_scope.order(updated_at: :desc).page(params[:page] || 1).per(per_page)
  end

  def show; end

  def create
    @doc = Current.account.crm_knowledge_docs.create!(doc_params.merge(owner_id: doc_params[:owner_id] || current_user.id))
  end

  def update
    @doc.update!(doc_params)
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

  def fetch_doc
    @doc = Current.account.crm_knowledge_docs.find(params[:id])
  end

  def check_authorization
    authorize(Crm::KnowledgeDoc)
  end

  # 视图：公司文档 / 我的知识库 / 文档看板按分类。
  def filtered_docs
    scope = Current.account.crm_knowledge_docs
    # 资料库隔离：销售资料 / 全公司知识。未传时不限（兼容旧调用）。
    scope = scope.in_library(params[:library]) if params[:library].present?
    scope = scope.company_docs if params[:filter] == 'company'
    scope = scope.personal_of(current_user.id) if params[:filter] == 'mine'
    scope = scope.where(category: params[:category]) if params[:category].present?
    scope = scope.where('name ILIKE :q OR summary ILIKE :q', q: "%#{params[:q]}%") if params[:q].present?
    scope
  end

  def doc_params
    params.require(:doc).permit(:name, :category, :summary, :scope, :library, :body, :owner_id, files: [])
  end

  # 看板视图一次拉全（上限 200）；未传时回落默认页大小。
  def per_page
    [(params[:per_page].presence || RESULTS_PER_PAGE).to_i, 200].min
  end
end
