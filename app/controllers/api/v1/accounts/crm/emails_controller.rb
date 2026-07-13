class Api::V1::Accounts::Crm::EmailsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_email, only: [:show, :update, :destroy, :attach_kb]

  RESULTS_PER_PAGE = 25

  def index
    @emails_scope = filtered_emails
    @emails_count = @emails_scope.count
    @emails = @emails_scope
              .includes(:crm_customer, :owner)
              .order(email_date: :desc)
              .page(permitted_params[:page] || 1)
              .per(RESULTS_PER_PAGE)
  end

  # 左栏文件夹计数（各文件夹总数 + 收件箱未读），一次查询喂列表页角标。
  def counts
    scope = Current.account.crm_emails
    by_folder = scope.group(:folder).count
    render json: {
      INBOX: by_folder['INBOX'].to_i,
      SENT: by_folder['SENT'].to_i,
      DRAFT: by_folder['DRAFT'].to_i,
      BULK: by_folder['BULK'].to_i,
      unread: scope.unread.count,
      starred: scope.starred.count
    }
  end

  def show; end

  # 知识库附件快照：把选中的知识库文档文件复制进本邮件附件，锁定当前版本
  # （不共享 blob，避免知识库原件被改/删影响已发邮件）。
  def attach_kb
    ids = Array(params[:file_ids]).map(&:to_i).uniq
    doc_ids = Current.account.crm_knowledge_docs.select(:id)
    ActiveStorage::Attachment.where(id: ids, record_type: 'Crm::KnowledgeDoc', record_id: doc_ids).find_each do |att|
      att.blob.open do |file|
        @email.files.attach(io: file, filename: att.filename.to_s, content_type: att.blob.content_type)
      end
    end
    render 'api/v1/accounts/crm/emails/show'
  end

  def create
    @email = Current.account.crm_emails.create!(email_params.merge(owner_id: email_params[:owner_id] || current_user.id))
  end

  def update
    @email.update!(email_params)
  end

  def destroy
    @email.destroy!
    head :ok
  end

  private

  def fetch_email
    @email = Current.account.crm_emails.find(params[:id])
  end

  def check_authorization
    authorize(Crm::Email)
  end

  # 阅读邮件视图筛选：全部/收件箱/未读/发件箱/草稿/群发、我的、按客户、搜主题/邮箱。
  def filtered_emails
    scope = Current.account.crm_emails
    scope = scope.in_folder(params[:folder]) if params[:folder].present?
    scope = scope.unread if params[:filter] == 'unread'
    scope = scope.starred if params[:filter] == 'starred'
    scope = scope.owned_by(current_user.id) if params[:filter] == 'mine'
    scope = scope.where(crm_customer_id: params[:customer_id]) if params[:customer_id].present?
    if params[:q].present?
      scope = scope.where('subject ILIKE :q OR from_address ILIKE :q OR to_address ILIKE :q', q: "%#{params[:q]}%")
    end
    scope
  end

  def email_params
    params.require(:email).permit(
      :subject, :folder, :is_read, :is_starred, :from_address, :to_address, :cc_address, :bcc_address,
      :email_date, :body, :body_html, :send_now, :send_status, :send_error,
      :crm_customer_id, :contact_id, :owner_id
    )
  end

  def permitted_params
    params.permit(:page, :folder, :filter, :customer_id, :q)
  end
end
