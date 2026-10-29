module UserAttributeHelpers
  extend ActiveSupport::Concern

  def available_name
    self[:display_name].presence || name
  end

  # CRM 专用显示名：CRM 界面 / 对外邮件发件人用英文名；未设置则回退中文 name。
  def crm_display_name
    self[:crm_name].presence || name
  end

  # 财务专用显示名：**中文优先**，没有中文名才回退英文。
  #
  # 和 crm_display_name 正好相反，这是有意的：CRM/对外邮件对的是老外客户，用英文名；
  # 财务对的是报税、做账、跟人核对，看到「Viki Wan / Jacky Zhang」认不出是谁
  # （14 个业务员里 10 个设了英文名，财务 2026-10-29 直接反馈「业务员中文名也没改」）。
  #
  # ⚠️ 凡是财务看的页面（应收/应付台账、记账凭证、出库审核、成本毛利）一律用这个，
  # 别再各写各的 `crm_name.presence || name` —— 原先四处抄了四遍，还抄反了三处。
  def finance_display_name
    name.presence || self[:crm_name]
  end

  def availability_status
    current_account_user&.availability_status
  end

  def auto_offline
    current_account_user&.auto_offline
  end

  def inviter
    current_account_user&.inviter
  end

  def active_account_user
    account_users.order(Arel.sql('active_at DESC NULLS LAST'))&.first
  end

  def current_account_user
    # We want to avoid subsequent queries in case where the association is preloaded.
    # using where here will trigger n+1 queries.
    account_users.find { |ac_usr| ac_usr.account_id == Current.account.id } if Current.account
  end

  def account
    current_account_user&.account
  end

  def administrator?
    current_account_user&.administrator?
  end

  def agent?
    current_account_user&.agent?
  end

  def role
    current_account_user&.role
  end

  # Used internally for Chatwoot in Chatwoot
  def hmac_identifier
    hmac_key = GlobalConfig.get('CHATWOOT_INBOX_HMAC_KEY')['CHATWOOT_INBOX_HMAC_KEY']
    return OpenSSL::HMAC.hexdigest('sha256', hmac_key, email) if hmac_key.present?

    ''
  end
end
