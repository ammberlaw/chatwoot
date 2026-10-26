# 收信黑名单：管理谁的信直接不收。
class Api::V1::Accounts::Crm::MailBlocklistsController < Api::V1::Accounts::BaseController
  before_action :set_rule, only: [:destroy]

  def index
    authorize Crm::MailBlocklist
    @rules = Current.account.crm_mail_blocklists.order(blocked_count: :desc, id: :desc)
    render json: { payload: @rules.map { |r| serialize(r) }, suggestions: suggestions }
  end

  def create
    authorize Crm::MailBlocklist
    value = params.require(:mail_blocklist).permit(:value, :note)
    reason = Crm::MailBlocklist.rejection_reason(Current.account, value[:value])
    return render json: { error: reason }, status: :unprocessable_entity if reason

    rule = Current.account.crm_mail_blocklists
                  .create!(value: value[:value], note: value[:note], created_by_id: current_user.id)
    # 新规则只挡以后的信；已经躺在收件箱里的同域邮件顺手挪进垃圾箱，
    # 否则「拉黑了怎么还在」。挪不删——万一拉错了还找得回来。
    render json: { payload: serialize(rule), swept: sweep_existing(rule) }
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    render json: { error: '这条规则已经在名单里了' }, status: :unprocessable_entity
  end

  def destroy
    authorize Crm::MailBlocklist
    @rule.destroy!
    head :ok
  end

  private

  def set_rule
    @rule = Current.account.crm_mail_blocklists.find(params[:id])
  end

  def serialize(rule)
    { id: rule.id, value: rule.value, note: rule.note,
      created_by_name: rule.created_by&.crm_display_name || rule.created_by&.name,
      blocked_count: rule.blocked_count, last_blocked_at: rule.last_blocked_at,
      last_blocked_from: rule.last_blocked_from, last_blocked_subject: rule.last_blocked_subject,
      created_at: rule.created_at }
  end

  # 把已在收件箱的同一发件方邮件挪进垃圾箱，返回挪了几封。
  def sweep_existing(rule)
    scope = Current.account.crm_emails.where(folder: 'INBOX')
    hits = scope.select { |e| rule.matches?(Crm::MailBlocklist.sender_address(e.from_address)) }.map(&:id)
    return 0 if hits.empty?

    Crm::Email.where(id: hits).update_all(folder: 'SPAM', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    hits.size
  end

  # 建议拉黑：这个域名的信**全部**被人标成了垃圾邮件。
  # 只推全中的——像 sales.alibaba.com 那种「3 封垃圾 22 封正常」的混合域，
  # 推上去就等着误伤；gmail.com 那种更是一条规则掐掉几百封客户来信。
  #
  # 在库里聚合，不要把几万行 from_address 拉回 Ruby 再数。
  SUGGEST_SQL = <<~SQL.squish.freeze
    SELECT lower(split_part(regexp_replace(from_address, '^.*<|>.*$', '', 'g'), '@', 2)) AS domain,
           count(*) FILTER (WHERE folder = 'SPAM') AS spam_count
    FROM crm_emails
    WHERE account_id = :account_id AND folder IN ('INBOX', 'SPAM')
    GROUP BY 1
    HAVING count(*) FILTER (WHERE folder = 'SPAM') > 0
       AND count(*) FILTER (WHERE folder = 'INBOX') = 0
    ORDER BY 2 DESC
    LIMIT 20
  SQL

  def suggestions
    sql = ActiveRecord::Base.sanitize_sql_array([SUGGEST_SQL, { account_id: Current.account.id }])
    rows = ActiveRecord::Base.connection.select_all(sql).to_a
    skip = Current.account.crm_mail_blocklists.pluck(:value) + Crm::MailBlocklist::FREE_MAIL_DOMAINS +
           Crm::MailBlocklist.own_domains(Current.account)
    rows.reject { |r| r['domain'].blank? || skip.include?(r['domain']) }
        .first(10)
        .map { |r| { value: r['domain'], spam_count: r['spam_count'].to_i } }
  end
end
