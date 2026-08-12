class Api::V1::Accounts::Crm::EmailsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_email, only: [:show, :update, :destroy, :attach_kb, :opens, :eml]

  RESULTS_PER_PAGE = 25

  def index
    @emails_scope = filtered_emails
    @emails_count = @emails_scope.count
    @emails = @emails_scope
              .includes(:crm_customer, :owner)
              .order(email_date: :desc)
              .page(permitted_params[:page] || 1)
              .per(page_size)
    @counterparty_types = build_counterparty_types(@emails)
    @last_opens = last_opens_for(@emails)
  end

  # 左栏文件夹计数（各文件夹总数 + 收件箱未读），一次查询喂列表页角标。
  # can_view_team：当前用户是否能看「团队邮件」（系统管理员或 CRM 团队负责人）——前端据此显示「我的/团队」切换。
  def counts
    ids = crm_mail_visible_owner_ids
    scope = visible_emails
    scope = scope.owned_by(params[:owner_id]) if params[:owner_id].present?
    scope = scope.where.not(owner_id: params[:exclude_owner_id]) if params[:exclude_owner_id].present?
    scope = filter_by_mailbox(scope) if params[:mailbox].present?
    # 系统文件夹角标排除已移入自定义文件夹的邮件（与列表移动语义一致）。
    scope = scope.where(crm_email_folder_id: nil)
    by_folder = scope.group(:folder).count
    render json: {
      INBOX: by_folder['INBOX'].to_i,
      SENT: by_folder['SENT'].to_i,
      DRAFT: by_folder['DRAFT'].to_i,
      BULK: by_folder['BULK'].to_i,
      SPAM: by_folder['SPAM'].to_i,
      unread: scope.unread.count,
      starred: scope.starred.count,
      can_view_team: ids == :all || ids.size > 1
    }
  end

  # 只列「本人在邮箱账户里配置的邮箱」+ 当前文件夹下各邮箱的邮件数（含主账号，各看各的）。
  def mailboxes
    accounts = Current.account.crm_mail_accounts.owned_by(current_user.id)
    scope = mailbox_count_scope
    render json: accounts.order(:id).map { |a|
      addr = a.email_address
      count = scope.where('from_address = :m OR to_address ILIKE :l', m: addr, l: "%#{addr}%").count
      { address: addr, name: a.name, count: count }
    }
  end

  # 邮箱计数口径：本人邮件、同一文件夹/视图（未读/星标/收件箱/发件箱…）。
  def mailbox_count_scope
    scope = Current.account.crm_emails.owned_by(current_user.id)
    scope = apply_view_filter(scope)
    scope = scope.in_folder(params[:folder]) if params[:folder].present?
    scope
  end

  # 手动收取：立即为当前用户的启用收件邮箱各排一个拉取任务（异步），前端稍后刷新列表。
  # 相对每分钟的定时轮询，给用户一个「立刻收信」的实时手段。
  def fetch
    ids = Current.account.crm_mail_accounts.owned_by(current_user.id).imap_active.pluck(:id)
    ids.each { |id| Crm::FetchImapEmailsJob.perform_later(id) }
    render json: { enqueued: ids.size }
  end

  def show
    @counterparty_type = counterparty_type_for(@email)
  end

  # 作为附件转发：把本邮件重建成 RFC822 .eml（含原附件）返回，前端拿去当新邮件的附件。
  def eml
    mail = Mail.new
    mail.from    = @email.from_address if @email.from_address.present?
    mail.to      = @email.to_address if @email.to_address.present?
    mail.cc      = @email.cc_address if @email.cc_address.present?
    mail.subject = @email.subject.presence || '(无主题)'
    mail.date    = @email.email_date if @email.email_date.present?
    if @email.body_html.present?
      mail.html_part = Mail::Part.new(body: @email.body_html, content_type: 'text/html; charset=UTF-8')
      mail.text_part = Mail::Part.new(body: @email.body.to_s, content_type: 'text/plain; charset=UTF-8')
    else
      mail.body = @email.body.to_s
      mail.charset = 'UTF-8'
    end
    @email.files.each { |file| mail.add_file(filename: file.filename.to_s, content: file.download) }
    name = "#{@email.subject.presence || 'email'}.eml".gsub(%r{[/\\:*?"<>|]}, '_')
    send_data mail.to_s, filename: name, type: 'message/rfc822', disposition: 'attachment'
  end

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
    @counterparty_type = counterparty_type_for(@email)
    render 'api/v1/accounts/crm/emails/show'
  end

  def create
    @email = Current.account.crm_emails.create!(email_params.merge(owner_id: email_params[:owner_id] || current_user.id))
    @counterparty_type = counterparty_type_for(@email)
  end

  # 更新：文字字段就地改；带来的新附件走 attach 追加（不覆盖已有附件，
  # 因 has_many_attached 直接赋值会整组替换，编辑草稿再传附件会丢原件）。
  def update
    new_files = email_params[:files]
    @email.update!(email_params.except(:files))
    Array(new_files).compact_blank.each { |file| @email.files.attach(file) }
    @counterparty_type = counterparty_type_for(@email)
  end

  def destroy
    @email.destroy!
    head :ok
  end

  # 批量移动到自定义文件夹（email_folder_id 为空=移出文件夹回到系统视图）。只动可见邮件。
  def move_to_folder
    folder_id = params[:email_folder_id].presence
    if folder_id && !Current.account.crm_email_folders.owned_by(current_user.id).exists?(id: folder_id)
      return render json: { error: '文件夹不存在' }, status: :unprocessable_entity
    end

    visible_emails.where(id: Array(params[:ids])).update_all(crm_email_folder_id: folder_id, updated_at: Time.current)
    head :ok
  end

  private

  def fetch_email
    @email = visible_emails.find(params[:id])
  end

  def check_authorization
    authorize(Crm::Email)
  end

  # 可见范围（邮件私密口径）：系统管理员看全员；CRM 团队负责人看本团队；其余只看自己。
  def visible_emails
    scope_by_mail_owner(Current.account.crm_emails)
  end

  # 阅读邮件视图筛选：文件夹/未读/星标/我的、按业务员（管理员）、按客户、搜主题/邮箱。
  def filtered_emails
    scope = apply_scope_filters(visible_emails)
    if params[:email_folder_id].present?
      # 自定义文件夹视图：只看该文件夹内的邮件。
      scope = scope.where(crm_email_folder_id: params[:email_folder_id])
    else
      # 系统视图（收件箱/发件箱等）排除已移入自定义文件夹的邮件（移动语义）。
      scope = scope.where(crm_email_folder_id: nil)
      scope = scope.in_folder(params[:folder]) if params[:folder].present?
    end
    scope = search_emails(scope, params[:q]) if params[:q].present?
    scope
  end

  # 视图 filter（未读/星标/我的）+ 按业务员 + 排除某人 + 按客户 + 按邮箱。
  def apply_scope_filters(scope)
    scope = apply_view_filter(scope)
    scope = scope.owned_by(params[:owner_id]) if params[:owner_id].present?
    # 团队邮件（未指定成员）排除自己——自己的在「我的邮件」里。
    scope = scope.where.not(owner_id: params[:exclude_owner_id]) if params[:exclude_owner_id].present?
    scope = filter_by_mailbox(scope) if params[:mailbox].present?
    scope = scope.where(crm_customer_id: params[:customer_id]) if params[:customer_id].present?
    # 追踪视图的「已打开/未打开」分栏。
    scope = scope.where('open_count > 0') if params[:opened] == '1'
    scope = scope.where(open_count: 0) if params[:opened] == '0'
    scope
  end

  # 追踪视图列表用：每封邮件最近一次打开的归属地（一次 DISTINCT ON 查询，避免逐行查库）。
  def last_opens_for(emails)
    return {} unless params[:filter] == 'tracking'

    ids = emails.map(&:id)
    return {} if ids.empty?

    Crm::EmailOpen.where(crm_email_id: ids)
                  .select('DISTINCT ON (crm_email_id) crm_email_id, country, city, created_at')
                  .order('crm_email_id, created_at DESC')
                  .index_by(&:crm_email_id)
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
    # 追踪视图：已发送且埋了追踪像素的邮件（能统计打开）。
    when 'tracking' then scope.where(folder: 'SENT').where.not(tracking_token: nil)
    else scope
    end
  end

  def search_emails(scope, query)
    scope.where('subject ILIKE :q OR from_address ILIKE :q OR to_address ILIKE :q', q: "%#{query}%")
  end

  def email_params
    params.require(:email).permit(
      :subject, :folder, :is_read, :is_starred, :from_address, :to_address, :cc_address, :bcc_address,
      :email_date, :body, :body_html, :send_now, :send_status, :send_error, :scheduled_at,
      :crm_customer_id, :contact_id, :owner_id, files: []
    )
  end

  # 每页条数：默认 25；列表页按日期分组需一次多取，允许 per_page 覆盖（上限 200）。
  def page_size
    req = permitted_params[:per_page].to_i
    req.positive? ? [req, 200].min : RESULTS_PER_PAGE
  end

  def permitted_params
    params.permit(:page, :per_page, :folder, :filter, :opened, :customer_id, :owner_id, :exclude_owner_id, :q, :email_folder_id)
  end

  # 列表头像按「对方」身份着色，与邮箱身份识别悬浮卡同口径：
  # 同事 / 我的客户 / 公海 / 同事客户(撞单) / 陌生人。整页批量解析，避免逐行查库。
  def build_counterparty_types(emails)
    addresses = emails.to_h { |e| [e.id, counterparty_address(e)] }
    lookup = addresses.values.compact.map(&:downcase).uniq
    return {} if lookup.empty?

    colleagues = Current.account.users.where('LOWER(users.email) IN (?)', lookup)
                        .pluck(Arel.sql('LOWER(users.email)')).to_set
    customers = Current.account.crm_customers.where('LOWER(contact_email) IN (?)', lookup)
                       .pluck(Arel.sql('LOWER(contact_email)'), :is_in_public_pool, :account_owner_id)
                       .index_by(&:first)

    addresses.transform_values { |addr| classify_counterparty(addr&.downcase, colleagues, customers) }
  end

  # 单封邮件的对方身份（show/update/create 用），复用批量口径。
  def counterparty_type_for(email)
    build_counterparty_types([email])[email.id]
  end

  # 收件箱看发件人，其余看收件人；地址串取第一个邮箱。
  def counterparty_address(email)
    raw = email.folder == 'INBOX' ? email.from_address : email.to_address
    raw.to_s.split(/[;,]/).map(&:strip).find(&:present?)
  end

  def classify_counterparty(addr, colleagues, customers)
    return 'stranger' if addr.blank?
    return 'colleague' if colleagues.include?(addr)

    _email, in_pool, owner_id = customers[addr]
    return 'stranger' if _email.nil?
    return 'public' if in_pool
    return 'mine' if owner_id == current_user.id

    'other'
  end
end
