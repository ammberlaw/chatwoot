class Api::V1::Accounts::Crm::KnowledgeDocsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_doc, only: [:show, :update, :destroy, :attach, :detach]

  RESULTS_PER_PAGE = 20

  def index
    @docs_scope = filtered_docs
    @docs_count = @docs_scope.count
    @docs = @docs_scope.order(updated_at: :desc).page(params[:page] || 1).per(RESULTS_PER_PAGE)
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
    scope = scope.company_docs if params[:filter] == 'company'
    scope = scope.personal_of(current_user.id) if params[:filter] == 'mine'
    scope = scope.where(category: params[:category]) if params[:category].present?
    scope = scope.where('name ILIKE :q OR summary ILIKE :q', q: "%#{params[:q]}%") if params[:q].present?
    scope
  end

  def doc_params
    params.require(:doc).permit(:name, :category, :summary, :scope, :body, :owner_id, files: [])
  end
end
