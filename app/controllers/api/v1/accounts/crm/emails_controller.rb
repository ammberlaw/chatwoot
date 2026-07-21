class Api::V1::Accounts::Crm::EmailsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_email, only: [:show, :update, :destroy, :attach_kb, :opens]

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
    scope = visible_emails
    scope = scope.owned_by(params[:owner_id]) if params[:owner_id].present?
    scope = filter_by_mailbox(scope) if params[:mailbox].present?
    by_folder = scope.group(:folder).count
    render json: {
      INBOX: by_folder['INBOX'].to_i,
      SENT: by_folder['SENT'].to_i,
      DRAFT: by_folder['DRAFT'].to_i,
      BULK: by_folder['BULK'].to_i,
      SPAM: by_folder['SPAM'].to_i,
      unread: scope.unread.count,
      starred: scope.starred.count
    }
  end

  # 可见范围内的邮箱列表 + 当前文件夹下各邮箱的邮件数（供左栏各邮箱切换）。
  def mailboxes
    accounts = scope_by_owner(Current.account.crm_mail_accounts)
    accounts = accounts.owned_by(params[:owner_id]) if params[:owner_id].present?
    scope = mailbox_count_scope
    render json: accounts.order(:id).map { |a|
      addr = a.email_address
      count = scope.where('from_address = :m OR to_address ILIKE :l', m: addr, l: "%#{addr}%").count
      { address: addr, name: a.name, count: count }
    }
  end

  # 邮箱计数口径：跟主列表同一文件夹/视图（未读/星标/收件箱/发件箱…），不含 mailbox 自身。
  def mailbox_count_scope
    scope = visible_emails
    scope = scope.owned_by(params[:owner_id]) if params[:owner_id].present?
    scope = apply_view_filter(scope)
    scope = scope.in_folder(params[:folder]) if params[:folder].present?
    scope
  end

  def show; end

  # 阅读追踪明细：每次打开的时间 + IP + UA（倒序）。
  def opens
    rows = @email.opens.order(created_at: :desc).limit(100).map do |open|
      { id: open.id, ip: open.ip_address, city: open.city, country: open.country,
        user_agent: open.user_agent, created_at: open.created_at }
    end
    render json: { payload: rows }
  end

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
    @email = visible_emails.find(params[:id])
  end

  def check_authorization
    authorize(Crm::Email)
  end

  # 可见范围（按 CRM 角色）：管理员看全员；主管看团队；业务员看自己的。
  def visible_emails
    scope_by_owner(Current.account.crm_emails)
  end

  # 阅读邮件视图筛选：文件夹/未读/星标/我的、按业务员（管理员）、按客户、搜主题/邮箱。
  def filtered_emails
    scope = apply_scope_filters(visible_emails)
    scope = scope.in_folder(params[:folder]) if params[:folder].present?
    scope = search_emails(scope, params[:q]) if params[:q].present?
    scope
  end

  # 视图 filter（未读/星标/我的）+ 按业务员 + 按客户 + 按邮箱。
  def apply_scope_filters(scope)
    scope = apply_view_filter(scope)
    scope = scope.owned_by(params[:owner_id]) if params[:owner_id].present?
    scope = filter_by_mailbox(scope) if params[:mailbox].present?
    scope = scope.where(crm_customer_id: params[:customer_id]) if params[:customer_id].present?
    scope
  end

  # 按邮箱地址收口：发件箱看 from，其余看 to（收件人含该邮箱）。
  def filter_by_mailbox(scope)
    m = params[:mailbox]
    scope.where('from_address = :m OR to_address ILIKE :like', m: m, like: "%#{m}%")
  end

  def apply_view_filter(scope)
    case params[:filter]
    when 'unread' then scope.unread
    when 'starred' then scope.starred
    when 'mine' then scope.owned_by(current_user.id)
    else scope
    end
  end

  def search_emails(scope, query)
    scope.where('subject ILIKE :q OR from_address ILIKE :q OR to_address ILIKE :q', q: "%#{query}%")
  end

  def email_params
    params.require(:email).permit(
      :subject, :folder, :is_read, :is_starred, :from_address, :to_address, :cc_address, :bcc_address,
      :email_date, :body, :body_html, :send_now, :send_status, :send_error,
      :crm_customer_id, :contact_id, :owner_id, files: []
    )
  end

  def permitted_params
    params.permit(:page, :folder, :filter, :customer_id, :owner_id, :q)
  end
end
