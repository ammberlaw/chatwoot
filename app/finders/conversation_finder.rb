# CRM 会话视图分支（见 Crm::ConversationViews）让本类略超行数限制，整体内聚故豁免。
# rubocop:disable Metrics/ClassLength
class ConversationFinder
  attr_reader :current_user, :current_account, :params

  DEFAULT_STATUS = 'open'.freeze
  SORT_OPTIONS = {
    'last_activity_at_asc' => %w[sort_on_last_activity_at asc],
    'last_activity_at_desc' => %w[sort_on_last_activity_at desc],
    'created_at_asc' => %w[sort_on_created_at asc],
    'created_at_desc' => %w[sort_on_created_at desc],
    'priority_asc' => %w[sort_on_priority asc],
    'priority_desc' => %w[sort_on_priority desc],
    'waiting_since_asc' => %w[sort_on_waiting_since asc],
    'waiting_since_desc' => %w[sort_on_waiting_since desc],
    'priority_desc_created_at_asc' => %w[sort_on_priority_created_at desc],
    'unread' => %w[sort_on_unread desc],

    # To be removed in v3.5.0
    'latest' => %w[sort_on_last_activity_at desc],
    'sort_on_created_at' => %w[sort_on_created_at asc],
    'sort_on_priority' => %w[sort_on_priority desc],
    'sort_on_waiting_since' => %w[sort_on_waiting_since asc]
  }.with_indifferent_access
  # assumptions
  # inbox_id if not given, take from all conversations, else specific to inbox
  # assignee_type if not given, take 'all'
  # conversation_status if not given, take 'open'

  # response of this class will be of type
  # {conversations: [array of conversations], count: {open: count, resolved: count}}

  # params
  # assignee_type, inbox_id, :status

  def initialize(current_user, params)
    @current_user = current_user
    @current_account = current_user.account
    @is_admin = current_account.account_users.find_by(user_id: current_user.id)&.administrator?
    @params = params
  end

  # 只要「当前用户看得见的会话」这一层（不带状态/指派等列表筛选），给侧栏角标之类的统计用。
  # 和列表共用同一套可见范围，角标和点进去看到的条数才对得上。
  def visible_scope
    set_inboxes
    find_all_conversations.where(status: :open)
  end

  def perform
    set_up

    counts = conversation_counts
    filter_by_assignee_type

    { conversations: conversations, count: counts }
  end

  def perform_meta_only
    set_up

    { count: conversation_counts }
  end

  private

  def set_up
    set_inboxes
    set_team
    set_assignee_type

    find_all_conversations
    filter_by_status unless params[:q]
    filter_by_team
    filter_by_labels
    filter_by_query
    filter_by_source_id
  end

  def set_inboxes
    @inbox_ids = if params[:inbox_id]
                   @current_user.assigned_inboxes.where(id: params[:inbox_id])
                 else
                   @current_user.assigned_inboxes.pluck(:id)
                 end
  end

  def set_assignee_type
    @assignee_type = params[:assignee_type]
  end

  def set_team
    @team = current_account.teams.find(params[:team_id]) if params[:team_id]
  end

  def find_conversation_by_inbox
    @conversations = current_account.conversations

    # 没带 inbox_id＝「所有会话」：管理员也只看自己名下收件箱的会话（自己的号 + 自己派给业务的那些，
    # 派出去的仍留在自己箱里）。老板不需要时刻盯着全体业务员的聊天；要看某个业务员的号，
    # 从侧栏点进去那一箱，那时带着 inbox_id，照常看全。非管理员不动——他们本来就被
    # Conversations::Visibility 收口，再按收件箱卡一道会把「被拉进去参与」的那几条误删。
    if params[:inbox_id].blank?
      @conversations = @conversations.where(inbox_id: own_inbox_ids) if @is_admin && own_inbox_ids.any?
      return
    end

    @conversations = @conversations.where(inbox_id: @inbox_ids)
  end

  # 当前用户作为成员挂在哪些收件箱下。一个都没挂的管理员不设限，
  # 否则「所有会话」会莫名其妙全空，看着像坏了。
  def own_inbox_ids
    @own_inbox_ids ||= current_user.inboxes.where(account_id: current_account.id).pluck(:id)
  end

  # 置顶优先：先按「我钉过没有」排，再接原来的排序规则。
  # order 是追加的，所以这一句必须在 sort_on_* 之前；LEFT JOIN 用唯一索引 (user_id, conversation_id)，
  # 一条会话最多配一行，不会把结果撑出重复。
  def pin_first(scope)
    join = ActiveRecord::Base.sanitize_sql_array(
      ['LEFT JOIN conversation_pins ON conversation_pins.conversation_id = conversations.id
        AND conversation_pins.user_id = ?', current_user.id]
    )
    scope.joins(join).order(Arel.sql('conversation_pins.id IS NULL'))
  end

  def find_all_conversations
    find_conversation_by_inbox
    # Apply permission-based filtering
    @conversations = Conversations::PermissionFilterService.new(
      @conversations,
      current_user,
      current_account
    ).perform
    filter_by_conversation_type if params[:conversation_type]
    @conversations
  end

  def filter_by_assignee_type
    case @assignee_type
    when 'me'
      @conversations = @conversations.assigned_to(current_user)
    when 'unassigned'
      @conversations = @conversations.unassigned
    when 'assigned'
      @conversations = @conversations.assigned
    # 「已分配」页签＝我派给别人的。不用现成的 assigned（有负责人就算），是因为
    # 管理员的会话九成都挂着负责人（线上 101 条里 93 条），那样这个页签跟「所有的」
    # 几乎一模一样；排掉分给自己的才剩下「我交出去的」这批真正要盯的。
    when 'assigned_out'
      @conversations = @conversations.where.not(assignee_id: [nil, current_user.id])
    end
    @conversations
  end

  def filter_by_conversation_type
    case @params[:conversation_type]
    when 'mention'
      conversation_ids = current_account.mentions.where(user: current_user).pluck(:conversation_id)
      @conversations = @conversations.where(id: conversation_ids)
    when 'participating'
      @conversations = current_user.participating_conversations.where(account_id: current_account.id)
    when 'unattended'
      @conversations = @conversations.unattended
    # 我的客户/未建档/待跟进/高意向，以及 crm_source:<来源code>
    when *Crm::ConversationViews::TYPES, Crm::ConversationViews::SOURCE_TYPE
      @conversations = Crm::ConversationViews.new(account: current_account, user: current_user,
                                                  scope: @conversations).apply(@params[:conversation_type])
    end
    @conversations
  end

  # 列表搜索。业务员要找的九成是「某个客户的那条会话」，而不是「说过某句话的会话」——
  # 线上 185 条会话只能靠滚，连刚进来的新询盘都翻不到。所以 q 先按联系人匹配
  # （名字/手机通讯录备注名同一个字段、电话、邮箱），消息正文作为补充一起 OR 进去。
  #
  # 消息那部分走子查询而不是 joins：join 会按命中的消息条数把同一条会话复制好几行，
  # 原来那段正是如此（还把同一个 where 写了两遍），搜一个常见词列表里就全是重复项。
  def filter_by_query
    return if params[:q].blank?

    term = "%#{params[:q].strip}%"
    allowed_message_types = [Message.message_types[:incoming], Message.message_types[:outgoing]]
    matched_by_message = Message.where(message_type: allowed_message_types)
                                .where('messages.content ILIKE ?', term)
                                .select(:conversation_id)
    @conversations = @conversations.joins(:contact).where(
      'contacts.name ILIKE :q OR contacts.phone_number ILIKE :q OR contacts.email ILIKE :q OR conversations.id IN (:ids)',
      q: term, ids: matched_by_message
    )
  end

  def filter_by_status
    return if params[:status] == 'all'

    @conversations = @conversations.where(status: params[:status] || DEFAULT_STATUS)
  end

  def filter_by_team
    return unless @team

    @conversations = @conversations.where(team: @team)
  end

  def filter_by_labels
    return unless params[:labels]

    @conversations = @conversations.tagged_with(params[:labels], any: true)
  end

  def filter_by_source_id
    return unless params[:source_id]

    @conversations = @conversations.joins(:contact_inbox)
    @conversations = @conversations.where(contact_inboxes: { source_id: params[:source_id] })
  end

  def conversation_counts
    mine, unassigned, assigned_out, all = set_count_for_all_conversations
    {
      mine_count: mine,
      assigned_count: all - unassigned,
      unassigned_count: unassigned,
      # 「已分配」页签＝我派给别人的（见 filter_by_assignee_type）
      assigned_out_count: assigned_out,
      all_count: all
    }
  end

  def set_count_for_all_conversations
    return legacy_count_for_all_conversations if @conversations.limit_value || @conversations.offset_value || @conversations.eager_loading?

    counts = @conversations.unscope(:order).pick(
      Arel.sql("COUNT(*) FILTER (WHERE assignee_id = #{current_user.id})"),
      Arel.sql('COUNT(*) FILTER (WHERE assignee_id IS NULL)'),
      Arel.sql("COUNT(*) FILTER (WHERE assignee_id IS NOT NULL AND assignee_id <> #{current_user.id})"),
      Arel.sql('COUNT(*)')
    )
    counts || [0, 0, 0, 0]
  end

  def legacy_count_for_all_conversations
    [
      @conversations.assigned_to(current_user).count,
      @conversations.unassigned.count,
      @conversations.where.not(assignee_id: [nil, current_user.id]).count,
      @conversations.count
    ]
  end

  def current_page
    params[:page] || 1
  end

  def conversations_base_query
    @conversations.includes(
      :taggings, :inbox, { assignee: { avatar_attachment: [:blob] } }, { contact: { avatar_attachment: [:blob] } }, :team, :contact_inbox
    )
  end

  def conversations
    @conversations = pin_first(conversations_base_query)

    sort_by, sort_order = SORT_OPTIONS[params[:sort_by]] || SORT_OPTIONS['last_activity_at_desc']
    @conversations = @conversations.send(sort_by, sort_order)

    if params[:updated_within].present?
      @conversations.where('conversations.updated_at > ?', Time.zone.now - params[:updated_within].to_i.seconds)
    else
      @conversations.page(current_page).per(ENV.fetch('CONVERSATION_RESULTS_PER_PAGE', '25').to_i)
    end
  end
end
ConversationFinder.prepend_mod_with('ConversationFinder')
# rubocop:enable Metrics/ClassLength
