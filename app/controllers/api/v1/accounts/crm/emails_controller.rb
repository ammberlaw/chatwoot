class Api::V1::Accounts::Crm::EmailsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_email, only: [:show, :update, :destroy, :attach_kb, :opens, :eml, :distribute, :distributions, :thread]

  RESULTS_PER_PAGE = 25
  EMAIL_RE = /[^\s,;<>"']+@[^\s,;<>"']+/

  def index
    @emails_scope = filtered_emails
    @emails_count = @emails_scope.count
    @emails = @emails_scope
              .includes(:crm_customer, :owner)
              .order(email_date: :desc)
              .page(permitted_params[:page] || 1)
              .per(page_size)
    decorate_list!(@emails)
  end

  # 写信框预填：按当前收件人算出系统会强制补上的抄送（分发留档），发送前显示给用户，
  # 免得抄送在后端悄悄加上、用户到发出后才发现（见 forced_cc_for）。
  def forced_cc
    render json: { addresses: forced_cc_for(params[:to_address]) }
  end

  # 左栏文件夹计数（各文件夹总数 + 收件箱未读），一次查询喂列表页角标。
  # can_view_team：当前用户是否能看「团队邮件」（系统管理员或 CRM 团队负责人）——前端据此显示「我的/团队」切换。
  def counts
    ids = crm_mail_visible_owner_ids
    scope = visible_emails
    scope = scope.owned_by(params[:owner_id]) if params[:owner_id].present?
    scope = scope.where.not(owner_id: params[:exclude_owner_id]) if params[:exclude_owner_id].present?
    scope = filter_by_mailbox(scope) if params[:mailbox].present?
    # 系统文件夹角标排除已移入自定义文件夹的邮件（与列表移动语义一致）；
    # 未读/星标是跨文件夹的待办视图，仍要算上文件夹里的（见 CROSS_FOLDER_FILTERS）。
    in_system_folders = scope.where(crm_email_folder_id: nil)
    by_folder = in_system_folders.group(:folder).count
    render json: {
      INBOX: by_folder['INBOX'].to_i,
      SENT: by_folder['SENT'].to_i,
      DRAFT: by_folder['DRAFT'].to_i,
      BULK: by_folder['BULK'].to_i,
      SPAM: by_folder['SPAM'].to_i,
      unread: scope.unread.count,
      starred: scope.starred.count,
      distributed: Current.account.crm_email_distributions.to_user(current_user.id).count,
      distributed_by_me: Current.account.crm_email_distributions.where(from_user_id: current_user.id).distinct.count(:crm_email_id),
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

  # 会话线程：与本邮件同一往来的所有可见邮件（同客户，或无客户时同对方地址；主题归一后相同），
  # 按时间正序。实时计算不落库，对存量邮件立即生效；草稿不计入。
  def thread
    key = Crm::Email.normalize_thread(@email.subject)
    return render json: { payload: [] } if key.blank?

    @thread_emails = thread_candidates(@email)
                     .select { |e| Crm::Email.normalize_thread(e.subject) == key }
                     .sort_by { |e| e.email_date || e.created_at }
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
    blocked = poaching_blocked_recipients(email_params[:to_address])
    if blocked.any?
      return render json: { error: poaching_error(blocked) }, status: :unprocessable_entity
    end

    @email = Current.account.crm_emails.create!(
      email_params.merge(
        owner_id: current_user.id, # 归属强制本人：owner_id 不再由客户端传，杜绝伪造他人归属绕过可见性/撞单
        cc_address: merge_forced_cc(email_params[:cc_address], forced_cc_for(email_params[:to_address]))
      )
    )
    @counterparty_type = counterparty_type_for(@email)
  end

  # 更新：文字字段就地改；带来的新附件走 attach 追加（不覆盖已有附件，
  # 因 has_many_attached 直接赋值会整组替换，编辑草稿再传附件会丢原件）。
  def update
    if email_params[:to_address].present?
      blocked = poaching_blocked_recipients(email_params[:to_address])
      if blocked.any?
        return render json: { error: poaching_error(blocked) }, status: :unprocessable_entity
      end
    end

    new_files = email_params[:files]
    attrs = email_params.except(:files)
    # 草稿改为发送/编辑收件人时，同样强制补齐分发抄送。
    attrs[:cc_address] = merge_forced_cc(email_params[:cc_address], forced_cc_for(email_params[:to_address])) if email_params[:to_address].present?
    @email.update!(attrs)
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

  # 群发单显：给每个收件人各建一条独立邮件（各自单独 To，互相不可见），逐封投递。
  # 同一份正文/签名/附件复制到每封；folder=BULK 归入「群发箱」；send_status=PENDING 触发发送队列。
  def bulk_create
    recipients = parsed_bulk_recipients
    return render json: { error: '没有有效收件人（缺邮箱）' }, status: :unprocessable_entity if recipients.blank?

    files = Array(email_params[:files]).compact_blank
    base = email_params.except(:to_address, :crm_customer_id, :contact_id, :files, :folder, :send_status, :send_now)
    # 定时群发：scheduled_at 在未来 → 每封置 SCHEDULED（到点由 DispatchScheduledEmailsJob 转 PENDING 发送）；否则立即 PENDING。
    scheduled = email_params[:scheduled_at].present? && Time.zone.parse(email_params[:scheduled_at].to_s) > Time.zone.now
    status = scheduled ? 'SCHEDULED' : 'PENDING'
    count = 0
    recipients.each do |r|
      cust = r[:crm_customer_id].present? ? Current.account.crm_customers.find_by(id: r[:crm_customer_id]) : nil
      contact = r[:contact_id].present? ? Current.account.contacts.find_by(id: r[:contact_id]) : nil
      email = Current.account.crm_emails.new(
        base.merge(
          owner_id: current_user.id, # 归属强制本人(见 create)
          folder: 'BULK',
          to_address: r[:email],
          cc_address: merge_forced_cc(base[:cc_address], forced_cc_for(r[:email])),
          crm_customer_id: r[:crm_customer_id].presence,
          contact_id: r[:contact_id].presence,
          subject: fill_template_vars(base[:subject], cust, contact),
          body: fill_template_vars(base[:body], cust, contact),
          body_html: fill_template_vars(base[:body_html], cust, contact),
          send_status: status
        )
      )
      files.each { |f| email.files.attach(f) }
      email.save!
      count += 1
    end
    render json: { count: count, scheduled: scheduled }
  end

  # 内部分发：把本邮件（正文+附件）分发给公司内部同事查看（站内流转，不外发）。
  # 每个被分发人一条记录（去重、排除自己）+ 站内通知。附件不复制，被分发人查看的是同一封邮件。
  def distribute
    requested = Array(params[:user_ids]).map(&:to_i).uniq - [current_user.id]
    # 只分发给 CRM 成员(管理员或有 crm_role)——过滤掉无 CRM 权限的账号成员，
    # 避免把邮件分发给进不了 CRM、拿到通知也打不开的人（前端已限，后端兜底防越权/脏客户端）。
    user_ids = requested & crm_member_user_ids
    note = params[:note].to_s
    created = 0
    ActiveRecord::Base.transaction do
      Current.account.users.where(id: user_ids).each do |u|
        dist = @email.distributions.find_or_initialize_by(to_user_id: u.id)
        next if dist.persisted?

        dist.assign_attributes(account: Current.account, from_user_id: current_user.id, note: note.presence)
        dist.save!
        created += 1
        subj = @email.subject.presence || '(无主题)'
        crm_notify(u.id, "#{current_user.crm_display_name} 给你分发了一封邮件：#{subj}#{note.present? ? "（#{note}）" : ''}", ref: distributed_email_ref(subj))
      end
    end
    render json: { distributed: created }
  rescue ActiveRecord::RecordNotUnique
    # 并发/重复点击同一分发：忽略重复，返回本次实际新建数。
    render json: { distributed: created }
  end

  # 本邮件的分发历史（谁分给了谁 / 何时 / 备注）——供邮件详情展示。
  def distributions
    @distributions = @email.distributions.includes(:to_user, :from_user).order(created_at: :desc)
  end

  # 分发给我的邮件（含正文+附件），按分发时间倒序。复用邮件列表渲染。
  def distributed
    ids_recent = Current.account.crm_email_distributions
                        .to_user(current_user.id).order(created_at: :desc).pluck(:crm_email_id)
    @emails_count = ids_recent.size
    page = (permitted_params[:page] || 1).to_i
    ids_page = ids_recent.slice((page - 1) * page_size, page_size) || []
    @emails = Current.account.crm_emails.where(id: ids_page)
                     .includes(:crm_customer, :owner)
                     .sort_by { |e| ids_page.index(e.id) }
    decorate_list!(@emails)
    render :index
  end

  # 我分发的邮件（我作为分发人分给同事的那些邮件，去重按邮件），按分发时间倒序。
  # 供主管/管理员对照「分发给我的」查看自己下发过哪些。复用邮件列表渲染。
  def distributed_by_me
    ids_recent = Current.account.crm_email_distributions
                        .where(from_user_id: current_user.id)
                        .order(created_at: :desc).pluck(:crm_email_id).uniq
    @emails_count = ids_recent.size
    page = (permitted_params[:page] || 1).to_i
    ids_page = ids_recent.slice((page - 1) * page_size, page_size) || []
    @emails = Current.account.crm_emails.where(id: ids_page)
                     .includes(:crm_customer, :owner)
                     .sort_by { |e| ids_page.index(e.id) }
    decorate_list!(@emails)
    render :index
  end

  private

  # 分发通知挂上这封邮件，点一下直接打开它（见 Chat::NotifyService#notify）。
  def distributed_email_ref(subject)
    # customer_id 一并带上：邮件中心的深链要「客户 + 邮件」两个参数才能直接打开那一封，
    # 没关联客户的邮件就只跳到邮件中心（见前端 openRef）。
    { type: 'email', id: @email.id, label: '邮件', title: subject,
      subtitle: "#{current_user.crm_display_name} 分发", customer_id: @email.crm_customer_id }
  end

  # 可分发对象=本账号 CRM 成员的 user_id：管理员或已配 crm_role 的成员。
  def crm_member_user_ids
    Current.account.account_users
           .where('crm_role IS NOT NULL OR role = ?', AccountUser.roles[:administrator])
           .pluck(:user_id)
  end

  # 防撞单：收件邮箱若属于「别人建档且你够不到」的客户，则拦截发送（单发/群发/回复通用）。
  # 豁免：管理员·超管·副管（early return）/ 负责人本人 / 被共享 / 该客户负责人在你邮件可见范围（主管看本团队）。
  # 匹配按客户「主要联系邮箱」，无主/公海客户不拦（谁都能捡）。
  def poaching_blocked_recipients(to_string)
    au = Current.account_user
    return [] if au.nil? || au.administrator? || au.crm_deputy_admin?

    addrs = to_string.to_s.scan(/[^\s,;<>"']+@[^\s,;<>"']+/).map(&:downcase).uniq
    return [] if addrs.empty?

    visible = Crm::AccessScope.new(Current.account, au).mail_visible_owner_ids
    return [] if visible == :all

    uid = current_user.id
    addrs.filter_map do |addr|
      cust = Current.account.crm_customers
                    .where.not(account_owner_id: nil)
                    .where('lower(trim(contact_email)) = ?', addr)
                    .first
      next if cust.nil?
      next if cust.account_owner_id == uid
      next if cust.shared_user_ids.include?(uid)
      next if visible.include?(cust.account_owner_id)

      { email: addr, owner: cust.account_owner&.name }
    end
  end

  def poaching_error(blocked)
    list = blocked.map { |b| "#{b[:email]}（已被#{b[:owner] || '同事'}建档）" }.join('、')
    "无法发送：#{list}。该客户已被同事建档，需分发或共享给你后才能联系。"
  end

  # 强制抄送：客户不是业务员自己开发来的（老板分发了邮件、或把客户分配给了他）时，
  # 业务员再与这个客户往来一律抄送回给他的人，让老板留档在环。
  # 返回：给 to_string 里的客户发信时，必须强制加入 cc 的邮箱地址（可能多人）。
  def forced_cc_for(to_string)
    addrs = to_string.to_s.scan(EMAIL_RE).map(&:downcase).uniq
    return [] if addrs.empty?

    (cc_from_distributions(addrs) + cc_from_assigner(addrs)).uniq
  end

  # 来路一：老板把这个客户的某封邮件分发给了我。
  def cc_from_distributions(addrs)
    Current.account.crm_email_distributions
           .to_user(current_user.id).includes(:crm_email)
           .flat_map { |dist| cc_from_distribution(dist.crm_email, addrs) }
  end

  # 来路二：这个客户归我，但是同事分配给我的 —— 抄送分配人名下的发信邮箱。
  # 认领公海客户、以及自己分给自己都不算（分配人为空，见 CustomersController#reassign）。
  def cc_from_assigner(addrs)
    by_contact = Current.account.contacts.where('lower(email) IN (?)', addrs).pluck(:crm_customer_id).compact
    assigner_ids = Current.account.crm_customers
                          .where(account_owner_id: current_user.id)
                          .where('crm_customers.id IN (:ids) OR lower(trim(contact_email)) IN (:addrs)',
                                 ids: by_contact, addrs: addrs)
                          .where.not(assigned_by_id: [nil, current_user.id])
                          .distinct.pluck(:assigned_by_id)
    return [] if assigner_ids.empty?

    # 每位分配人只抄一个邮箱（默认邮箱优先）——有人名下配了五个，全抄等于给同一个人发五份。
    Current.account.crm_mail_accounts.where(owner_id: assigner_ids)
           .order(is_default: :desc, id: :asc)
           .group_by(&:owner_id).values.map { |boxes| boxes.first.email_address }
  end

  # 单条分发记录：若被分发邮件的对方(客户)命中本次收件人，返回分发人自有邮箱(应抄送地址)。
  # 对方侧：收件箱看发件人，其余看收件人；分发人侧则取相反的一侧。
  def cc_from_distribution(email, addrs)
    return [] if email.nil?

    inbox = email.folder == 'INBOX'
    # 对方地址按完整邮箱 token 精确比对（避免 include? 子串误命中：如 amber@x.com 命中 xamber@x.com，
    # 或对方是多地址串时错配），命中才回抄。
    counterparty = (inbox ? email.from_address : email.to_address).to_s.downcase.scan(EMAIL_RE)
    return [] if (addrs & counterparty).empty?

    # 回抄分发人自有侧的全部邮箱(多地址时不能只取第一个,否则老板留档漏抄)，
    # 但只认公司自有邮箱：客户的群发询盘会把同行的地址一起写在收件人栏里，
    # 整条收件人原样回抄，等于把我们的回复抄送给同行。
    own_side = (inbox ? email.to_address : email.from_address).to_s.scan(EMAIL_RE)
    own_side.select { |a| own_mailbox_addresses.include?(a.downcase) }
  end

  # 本账号已配置的自有发信邮箱（小写），强制抄送只允许落在这些地址上。
  def own_mailbox_addresses
    @own_mailbox_addresses ||= Current.account.crm_mail_accounts.pluck(:email_address)
                                      .compact_blank.map { |a| a.downcase.strip }
  end

  # 把强制抄送地址并入现有 cc 串（大小写去重、保留用户原填的抄送）。
  def merge_forced_cc(existing_cc, forced)
    return existing_cc if forced.blank?

    existing_set = existing_cc.to_s.scan(EMAIL_RE).map(&:downcase)
    add = forced.reject { |a| existing_set.include?(a.downcase) }
    return existing_cc if add.empty?

    [existing_cc.presence, *add].compact.join(', ')
  end

  # 邮件模板变量替换（群发按每个收件人的客户/联系人逐封填充）：
  # {{公司}}/{{客户名}}/{{客户} → 客户名；{{联系人}} → 联系人名；{{我的名字}}/{{我}}/{{发件人}} → 本人。
  # 未知/无值的变量保留原样。
  def fill_template_vars(text, customer, contact)
    return text if text.blank?

    company = customer&.name.to_s
    cname = contact&.name.presence || customer&.primary_contact_name.to_s
    me = current_user.crm_display_name.to_s
    text.gsub(/\{\{\s*(?:公司|客户名|客户)\s*\}\}/) { |m| company.presence || m }
        .gsub(/\{\{\s*联系人\s*\}\}/) { |m| cname.presence || m }
        .gsub(/\{\{\s*(?:我的名字|我|发件人)\s*\}\}/) { |m| me.presence || m }
  end

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

  # 未读/星标是跨文件夹的待办视图：归到自定义文件夹里的邮件也要出现在这两个视图里，
  # 否则把某个客户的邮件整理进文件夹后，他的新邮件就再也不在「未读」里提醒了。
  CROSS_FOLDER_FILTERS = %w[unread starred].freeze

  # 阅读邮件视图筛选：文件夹/未读/星标/我的、按业务员（管理员）、按客户、搜主题/邮箱。
  def filtered_emails
    scope = apply_scope_filters(visible_emails)
    if params[:email_folder_id].present?
      # 自定义文件夹视图：只看该文件夹内的邮件。
      scope = scope.where(crm_email_folder_id: params[:email_folder_id])
    elsif !CROSS_FOLDER_FILTERS.include?(params[:filter])
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
    scope = scope.with_label(params[:label_id]) if params[:label_id].present?
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

  # 搜索：主题 / 收发件人 / 抄送 / 正文（纯文本 + HTML）。正文匹配让业务员能按邮件内容
  # （产品名 / 报价 / 订单号等）翻回历史往来，而不只是主题和邮箱。
  def search_emails(scope, query)
    scope.where(
      'subject ILIKE :q OR from_address ILIKE :q OR to_address ILIKE :q OR cc_address ILIKE :q ' \
      'OR body ILIKE :q OR body_html ILIKE :q',
      q: "%#{query}%"
    )
  end

  # 群发收件人列表：[{ email, crm_customer_id?, contact_id? }, …]，兼容 JSON 字符串/数组两种传法。
  def parsed_bulk_recipients
    raw = params[:recipients]
    raw = JSON.parse(raw) if raw.is_a?(String)
    Array(raw).filter_map do |r|
      r = r.respond_to?(:to_unsafe_h) ? r.to_unsafe_h : r
      email = r['email'].presence || r[:email].presence
      next if email.blank?

      { email: email, crm_customer_id: r['crm_customer_id'] || r[:crm_customer_id],
        contact_id: r['contact_id'] || r[:contact_id] }
    end
  rescue JSON::ParserError
    []
  end

  def email_params
    params.require(:email).permit(
      :subject, :folder, :is_read, :is_starred, :from_address, :to_address, :cc_address, :bcc_address,
      :email_date, :body, :body_html, :send_now, :send_status, :send_error, :scheduled_at,
      :crm_customer_id, :contact_id, files: [], label_ids: []
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

    colleagues = lookup.empty? ? Set.new : Current.account.users.where('LOWER(users.email) IN (?)', lookup)
                                                  .pluck(Arel.sql('LOWER(users.email)')).to_set
    # 登录邮箱之外，同事配在系统里的收发邮箱也算同事（口径见 Crm::MailAccount.owner_names_by_address）。
    colleagues |= Crm::MailAccount.owner_names_by_address(Current.account, lookup).keys.to_set
    customers = lookup.empty? ? {} : Current.account.crm_customers.where('LOWER(contact_email) IN (?)', lookup)
                                            .pluck(Arel.sql('LOWER(contact_email)'), :is_in_public_pool, :account_owner_id)
                                            .index_by(&:first)

    # 已建档（邮件已挂客户）的直接按所挂客户判定：避免「客户主联系邮箱≠本次收发地址」时被误判成陌生人（灰头像）。
    linked_ids = emails.filter_map(&:crm_customer_id).uniq
    linked = linked_ids.empty? ? {} : Current.account.crm_customers.where(id: linked_ids)
                                             .pluck(:id, :is_in_public_pool, :account_owner_id).index_by(&:first)

    emails.to_h { |e| [e.id, classify_counterparty(e, addresses[e.id]&.downcase, colleagues, customers, linked)] }
  end

  # 列表显示「对方」时优先用业务员自己备注的联系人名（如「加拿大15寸触显-Michael」），
  # 一串邮箱地址认不出是谁。按地址批量查一次联系人，没有就退回客户名，再没有就显示地址。
  def build_counterparty_names(emails)
    addresses = emails.to_h { |e| [e.id, counterparty_address(e)&.downcase] }
    lookup = addresses.values.compact.uniq
    contacts = contact_names_by_address(lookup)
    # 同事的公司邮箱优先显示本人名字，否则列表上只剩一串 sales98@… 认不出是谁。
    colleagues = Crm::MailAccount.owner_names_by_address(Current.account, lookup)
    emails.to_h do |e|
      addr = addresses[e.id]
      [e.id, colleagues[addr] || contacts[addr] || e.crm_customer&.name]
    end
  end

  # 列表渲染要的那几组批量数据（对方身份/对方名/最近打开/分发去向），
  # index 与「分发给我的」「我分发的」都渲染同一个 index.json.jbuilder，必须一处备齐。
  def decorate_list!(emails)
    @counterparty_types = build_counterparty_types(emails)
    @counterparty_names = build_counterparty_names(emails)
    @last_opens = last_opens_for(emails)
    @distributions = distributions_for(emails)
  end

  # 内部分发去向：列表上直接标出这封分给了谁（像会话卡片标业务），不用点进去看分发历史。
  def distributions_for(emails)
    ids = emails.map(&:id)
    return {} if ids.empty?

    Current.account.crm_email_distributions.where(crm_email_id: ids)
           .includes(:to_user, :from_user).order(:created_at)
           .group_by(&:crm_email_id)
  end

  def contact_names_by_address(lookup)
    return {} if lookup.empty?

    Current.account.contacts.where('LOWER(contacts.email) IN (?)', lookup)
           .pluck(Arel.sql('LOWER(contacts.email)'), :name)
           .to_h.compact_blank
  end

  # 单封邮件的对方身份（show/update/create 用），复用批量口径。
  def counterparty_type_for(email)
    build_counterparty_types([email])[email.id]
  end

  # 线程候选集（再由主题归一精筛）：同客户则取该客户全部往来；无客户则取与对方地址收发相关的邮件。
  # 限量 300 封兜底，避免大账户全表 Ruby 过滤。
  def thread_candidates(email)
    scope = visible_emails.where.not(folder: 'DRAFT')
                          .includes(:owner, :crm_customer, files_attachments: :blob)
    if email.crm_customer_id
      scope.where(crm_customer_id: email.crm_customer_id).limit(300).to_a
    else
      addr = counterparty_address(email)
      return [email] if addr.blank?

      scope.where('from_address ILIKE :a OR to_address ILIKE :a', a: "%#{addr}%").limit(300).to_a
    end
  end

  # 收件箱看发件人，其余看收件人；地址串取第一个邮箱。
  def counterparty_address(email)
    raw = email.folder == 'INBOX' ? email.from_address : email.to_address
    raw.to_s.split(/[;,]/).map(&:strip).find(&:present?)
  end

  def classify_counterparty(email, addr, colleagues, customers, linked)
    return 'colleague' if addr.present? && colleagues.include?(addr)

    # 邮件已挂客户 → 按该客户着色（这是「建档」的最强信号，优先于地址匹配）；未挂客户再按地址匹配客户联系邮箱。
    row = (email.crm_customer_id && linked[email.crm_customer_id]) || (addr.present? && customers[addr])
    return 'stranger' if row.blank?

    _key, in_pool, owner_id = row
    return 'public' if in_pool
    return 'mine' if owner_id == current_user.id

    'other'
  end
end
