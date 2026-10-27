# 收信黑名单：管理谁的信直接不收。
#
# 两级：业务员拉黑只对自己生效（他自己的客户他自己判断，拦错了也只影响他）；
# 管理员/副管才能开全公司规则——一条全公司规则能掐掉同事的客户来信。
class Api::V1::Accounts::Crm::MailBlocklistsController < Api::V1::Accounts::BaseController
  before_action :set_rule, only: [:destroy]

  def index
    authorize Crm::MailBlocklist
    # 看得到：全公司的（只读）+ 自己的。管理员看得到全部，连别人的个人规则一起。
    scope = Current.account.crm_mail_blocklists
    scope = scope.effective_for(current_user.id) unless can_manage_global?
    @rules = scope.order(blocked_count: :desc, id: :desc)
    render json: { payload: @rules.map { |r| serialize(r) },
                   can_manage_global: can_manage_global?, suggestions: suggestions }
  end

  def create
    authorize Crm::MailBlocklist
    attrs = params.require(:mail_blocklist).permit(:value, :note, :scope)
    reason = Crm::MailBlocklist.rejection_reason(Current.account, attrs[:value])
    return render json: { error: reason }, status: :unprocessable_entity if reason

    # 只有管理员能开全公司规则；其余人一律落到自己名下（前端传什么都不作数）。
    owner_id = attrs[:scope] == 'global' && can_manage_global? ? nil : current_user.id
    rule = Current.account.crm_mail_blocklists
                  .create!(value: attrs[:value], note: attrs[:note],
                           owner_id: owner_id, created_by_id: current_user.id)
    # 新规则只挡以后的信；已经躺在收件箱里的同域邮件顺手挪进垃圾箱，
    # 否则「拉黑了怎么还在」。挪不删——万一拉错了还找得回来。
    render json: { payload: serialize(rule), swept: sweep_existing(rule) }
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    render json: { error: '这条规则已经在名单里了' }, status: :unprocessable_entity
  end

  def destroy
    authorize Crm::MailBlocklist
    # 自己的规则自己删；全公司规则和别人的个人规则只有管理员能动。
    return render json: { error: '这条规则是全公司生效的，只有管理员能取消' }, status: :forbidden unless removable?(@rule)

    @rule.destroy!
    head :ok
  end

  private

  def removable?(rule) = rule.owner_id == current_user.id || can_manage_global?

  def can_manage_global?
    Current.account_user.administrator? || Current.account_user.crm_deputy_admin?
  end

  def set_rule
    @rule = Current.account.crm_mail_blocklists.find(params[:id])
  end

  def serialize(rule)
    { id: rule.id, value: rule.value, note: rule.note,
      scope: rule.global? ? 'global' : 'mine', scope_label: rule.scope_label,
      can_remove: removable?(rule),
      created_by_name: rule.created_by&.crm_display_name || rule.created_by&.name,
      blocked_count: rule.blocked_count, last_blocked_at: rule.last_blocked_at,
      last_blocked_from: rule.last_blocked_from, last_blocked_subject: rule.last_blocked_subject,
      created_at: rule.created_at }
  end

  # 把已在收件箱的同一发件方邮件挪进垃圾箱，返回挪了几封。
  def sweep_existing(rule)
    scope = Current.account.crm_emails.where(folder: 'INBOX')
    # 个人规则只清自己名下的信，别动同事收件箱。
    scope = scope.where(owner_id: rule.owner_id) unless rule.global?
    hits = scope.select { |e| rule.matches?(Crm::MailBlocklist.sender_address(e.from_address)) }.map(&:id)
    return 0 if hits.empty?

    Crm::Email.where(id: hits).update_all(folder: 'SPAM', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    hits.size
  end

  # 建议拉黑：这个域名的信**全部**被标成了垃圾邮件。
  # 只推全中的——像 sales.alibaba.com 那种「3 封垃圾 22 封正常」的混合域，
  # 推上去就等着误伤；gmail.com 那种更是一条规则掐掉几百封客户来信。
  #
  # 业务员只按自己名下的信算：同一个域名在他那儿全是垃圾、在同事那儿是客户，
  # 按全公司算就谁都推不出来。管理员按全公司算。
  #
  # 在库里聚合，不要把几万行 from_address 拉回 Ruby 再数。
  SUGGEST_SQL = <<~SQL.squish.freeze
    SELECT lower(split_part(regexp_replace(from_address, '^.*<|>.*$', '', 'g'), '@', 2)) AS domain,
           count(*) FILTER (WHERE folder = 'SPAM') AS spam_count
    FROM crm_emails
    WHERE account_id = :account_id AND folder IN ('INBOX', 'SPAM')
      AND (:owner_id::bigint IS NULL OR owner_id = :owner_id)
    GROUP BY 1
    HAVING count(*) FILTER (WHERE folder = 'SPAM') > 0
       AND count(*) FILTER (WHERE folder = 'INBOX') = 0
    ORDER BY 2 DESC
    LIMIT 20
  SQL

  def suggestions
    rows = ActiveRecord::Base.connection.select_all(suggest_sql).to_a
    rows.reject { |r| r['domain'].blank? || suggest_skip.include?(r['domain']) }
        .first(10)
        .map { |r| { value: r['domain'], spam_count: r['spam_count'].to_i } }
  end

  def suggest_sql
    ActiveRecord::Base.sanitize_sql_array(
      [SUGGEST_SQL, { account_id: Current.account.id,
                      owner_id: can_manage_global? ? nil : current_user.id }]
    )
  end

  # 已经拉过的、公共邮箱域名、本公司域名，都不用再推。
  def suggest_skip
    Current.account.crm_mail_blocklists.effective_for(current_user.id).pluck(:value) +
      Crm::MailBlocklist::FREE_MAIL_DOMAINS + Crm::MailBlocklist.own_domains(Current.account)
  end
end
