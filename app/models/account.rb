# == Schema Information
#
# Table name: accounts
#
#  id                    :integer          not null, primary key
#  auto_resolve_duration :integer
#  custom_attributes     :jsonb
#  domain                :string(100)
#  feature_flags         :bigint           default(0), not null
#  internal_attributes   :jsonb            not null
#  limits                :jsonb
#  locale                :integer          default("en")
#  name                  :string           not null
#  settings              :jsonb
#  status                :integer          default("active")
#  support_email         :string(100)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Indexes
#
#  index_accounts_on_status  (status)
#

class Account < ApplicationRecord
  # used for single column multi flags
  include FlagShihTzu
  include Reportable
  include Featurable
  include CacheKeys
  include CaptainFeaturable
  include AccountEmailRateLimitable
  include AccountSettingsSchema

  DEFAULT_QUERY_SETTING = {
    flag_query_mode: :bit_operator,
    check_for_column: false
  }.freeze

  validates :name, presence: true
  # `domain` is the inbound email domain used to construct reply addresses
  # (see `inbound_email_domain`). Do not repurpose it for a website or any
  # non-mail-related domain.
  validates :domain, length: { maximum: 100 }
  validates_with JsonSchemaValidator,
                 schema: SETTINGS_PARAMS_SCHEMA,
                 attribute_resolver: ->(record) { record.settings }
  validate :validate_reporting_timezone
  validate :validate_support_email_format, if: :will_save_change_to_support_email?

  store_accessor :settings, :auto_resolve_after, :auto_resolve_message, :auto_resolve_ignore_waiting

  store_accessor :settings, :audio_transcriptions, :auto_resolve_label
  store_accessor :settings, :captain_models, :captain_features
  store_accessor :settings, :reporting_timezone
  store_accessor :settings, :keep_pending_on_bot_failure
  store_accessor :settings, :captain_auto_resolve_mode, :captain_false_promise_harness_enabled
  include AccountCaptainAutoResolve

  has_many :account_users, dependent: :destroy_async
  has_many :agent_bot_inboxes, dependent: :destroy_async
  has_many :agent_bots, dependent: :destroy_async
  has_many :api_channels, dependent: :destroy_async, class_name: '::Channel::Api'
  has_many :articles, dependent: :destroy_async, class_name: '::Article'
  has_many :assignment_policies, dependent: :destroy_async
  has_many :automation_rules, dependent: :destroy_async
  has_many :macros, dependent: :destroy_async
  has_many :campaigns, dependent: :destroy_async
  has_many :canned_responses, dependent: :destroy_async
  has_many :categories, dependent: :destroy_async, class_name: '::Category'
  has_many :contacts, dependent: :destroy_async
  has_many :conversations, dependent: :destroy_async
  has_many :crm_customers, class_name: 'Crm::Customer', dependent: :destroy_async
  has_many :crm_business_cards, class_name: 'Crm::BusinessCard', dependent: :destroy_async
  has_many :crm_opportunities, class_name: 'Crm::Opportunity', dependent: :destroy_async
  has_many :crm_products, class_name: 'Crm::Product', dependent: :destroy_async
  has_many :crm_sales_orders, class_name: 'Crm::SalesOrder', dependent: :destroy_async
  has_many :crm_quote_request_templates, class_name: 'Crm::QuoteRequestTemplate', dependent: :destroy_async
  has_many :crm_quote_requests, class_name: 'Crm::QuoteRequest', dependent: :destroy_async
  has_many :crm_pis, class_name: 'Crm::Pi', dependent: :destroy_async
  has_many :crm_pi_seller_profiles, class_name: 'Crm::PiSellerProfile', dependent: :destroy_async
  has_many :crm_quotes, class_name: 'Crm::Quote', dependent: :destroy_async
  has_many :crm_quote_line_items, class_name: 'Crm::QuoteLineItem', dependent: :destroy_async
  has_many :crm_emails, class_name: 'Crm::Email', dependent: :destroy_async
  # CRM AI 助手的对话（见 Crm::Agent::Runner）
  has_many :crm_agent_conversations, class_name: 'Crm::AgentConversation', dependent: :destroy_async
  has_many :crm_follow_up_notes, class_name: 'Crm::FollowUpNote', dependent: :destroy_async
  has_many :crm_follow_up_tasks, class_name: 'Crm::FollowUpTask', dependent: :destroy_async
  has_many :crm_schedule_events, class_name: 'Crm::ScheduleEvent', dependent: :destroy_async
  has_many :crm_product_aux_attributes, class_name: 'Crm::ProductAuxAttribute', dependent: :destroy_async
  has_many :crm_exhibitions, class_name: 'Crm::Exhibition', dependent: :destroy_async
  has_many :crm_exhibition_invites, class_name: 'Crm::ExhibitionInvite', dependent: :destroy_async
  has_many :crm_email_distributions, class_name: 'Crm::EmailDistribution', dependent: :destroy_async
  has_many :crm_knowledge_docs, class_name: 'Crm::KnowledgeDoc', dependent: :destroy_async
  has_many :crm_doc_sections, class_name: 'Crm::DocSection', dependent: :destroy_async
  has_many :erp_stock_layers, class_name: 'Erp::StockLayer', dependent: :destroy_async
  has_many :erp_stock_consumptions, class_name: 'Erp::StockConsumption', dependent: :destroy_async
  has_many :crm_credential_groups, class_name: 'Crm::CredentialGroup', dependent: :destroy_async
  has_many :crm_credentials, class_name: 'Crm::Credential', dependent: :destroy_async
  has_many :crm_credential_views, class_name: 'Crm::CredentialView', dependent: :destroy_async
  has_many :crm_member_invites, class_name: 'Crm::MemberInvite', dependent: :destroy_async
  has_many :crm_knowledge_categories, class_name: 'Crm::KnowledgeCategory', dependent: :destroy_async
  has_many :crm_teams, class_name: 'Crm::Team', dependent: :destroy_async
  has_many :crm_sales_targets, class_name: 'Crm::SalesTarget', dependent: :destroy_async
  has_many :crm_mail_accounts, class_name: 'Crm::MailAccount', dependent: :destroy_async
  has_many :crm_mail_blocklists, class_name: 'Crm::MailBlocklist', dependent: :destroy_async
  has_many :crm_email_templates, class_name: 'Crm::EmailTemplate', dependent: :destroy_async
  has_many :crm_email_signatures, class_name: 'Crm::EmailSignature', dependent: :destroy_async
  has_many :crm_email_folders, class_name: 'Crm::EmailFolder', dependent: :destroy_async
  has_many :crm_email_labels, class_name: 'Crm::EmailLabel', dependent: :destroy_async
  has_many :crm_quick_texts, class_name: 'Crm::QuickText', dependent: :destroy_async
  has_many :crm_kpi_schemes, class_name: 'Crm::KpiScheme', dependent: :destroy_async
  has_many :crm_scheme_items, class_name: 'Crm::SchemeItem', dependent: :destroy_async
  has_many :crm_payout_tiers, class_name: 'Crm::PayoutTier', dependent: :destroy_async
  has_many :crm_employee_comps, class_name: 'Crm::EmployeeComp', dependent: :destroy_async
  has_many :crm_employees, class_name: 'Crm::Employee', dependent: :destroy_async
  has_many :crm_access_logs, class_name: 'Crm::AccessLog', dependent: :destroy_async
  has_many :crm_attendance_records, class_name: 'Crm::AttendanceRecord', dependent: :destroy_async
  has_many :crm_attendance_groups, class_name: 'Crm::AttendanceGroup', dependent: :destroy_async
  has_many :crm_kpi_sheets, class_name: 'Crm::KpiSheet', dependent: :destroy_async
  has_many :crm_kpi_sheet_items, class_name: 'Crm::KpiSheetItem', dependent: :destroy_async
  has_many :crm_commission_sheets, class_name: 'Crm::CommissionSheet', dependent: :destroy_async
  has_many :crm_commission_items, class_name: 'Crm::CommissionItem', dependent: :destroy_async
  has_many :crm_commission_rates, class_name: 'Crm::CommissionRate', dependent: :destroy_async
  has_many :crm_signatures, class_name: 'Crm::Signature', dependent: :destroy_async
  has_many :crm_option_items, class_name: 'Crm::OptionItem', dependent: :destroy_async
  # 核价表（内部报价单）：按版本维护，业务员只读最新已发布版
  has_many :crm_price_lists, class_name: 'Crm::PriceList', dependent: :destroy_async
  has_many :crm_price_list_items, class_name: 'Crm::PriceListItem', dependent: :destroy_async
  has_many :crm_role_templates, class_name: 'Crm::RoleTemplate', dependent: :destroy_async
  # 备用金台账（按部门/项目分本，替代原 Excel）
  has_many :crm_petty_cash_books, class_name: 'Crm::PettyCashBook', dependent: :destroy_async
  has_many :crm_petty_cash_entries, class_name: 'Crm::PettyCashEntry', dependent: :destroy_async
  has_one :crm_performance_setting, class_name: 'Crm::PerformanceSetting', dependent: :destroy_async
  # TikTok 板块（店铺经营日报 + 利润表 + 部门）
  has_many :tiktok_departments, class_name: 'Tiktok::Department', dependent: :destroy_async
  has_many :tiktok_shops, class_name: 'Tiktok::Shop', dependent: :destroy_async
  has_many :tiktok_daily_sales_records, class_name: 'Tiktok::DailySalesRecord', dependent: :destroy_async
  has_many :tiktok_profit_records, class_name: 'Tiktok::ProfitRecord', dependent: :destroy_async
  # TK 支出台账与固定资产登记（TK 支出从 CRM 备用金台账里独立出来）
  has_many :tiktok_expenses, class_name: 'Tiktok::Expense', dependent: :destroy_async
  has_many :tiktok_assets, class_name: 'Tiktok::Asset', dependent: :destroy_async
  # ERP（财务管理）：会计科目表是记账地基，凭证/账簿/报表都挂它。
  has_many :erp_ledger_accounts, class_name: 'Erp::LedgerAccount', dependent: :destroy_async
  has_many :erp_vouchers, class_name: 'Erp::Voucher', dependent: :destroy_async
  has_many :erp_voucher_lines, class_name: 'Erp::VoucherLine', dependent: :destroy_async
  has_many :erp_receivables, class_name: 'Erp::Receivable', dependent: :destroy_async
  has_many :erp_receivable_installments, class_name: 'Erp::ReceivableInstallment', dependent: :destroy_async
  has_many :erp_receipt_records, class_name: 'Erp::ReceiptRecord', dependent: :destroy_async
  has_many :erp_receipt_allocations, class_name: 'Erp::ReceiptAllocation', dependent: :destroy_async
  has_many :erp_payables, class_name: 'Erp::Payable', dependent: :destroy_async
  has_many :erp_payment_records, class_name: 'Erp::PaymentRecord', dependent: :destroy_async
  has_many :erp_payment_allocations, class_name: 'Erp::PaymentAllocation', dependent: :destroy_async
  has_many :erp_cash_accounts, class_name: 'Erp::CashAccount', dependent: :destroy_async
  has_many :erp_cash_transactions, class_name: 'Erp::CashTransaction', dependent: :destroy_async
  has_many :erp_auto_voucher_rules, class_name: 'Erp::AutoVoucherRule', dependent: :destroy_async
  has_many :erp_fiscal_periods, class_name: 'Erp::FiscalPeriod', dependent: :destroy_async
  has_many :erp_fixed_assets, class_name: 'Erp::FixedAsset', dependent: :destroy_async
  has_many :erp_depreciation_entries, class_name: 'Erp::DepreciationEntry', dependent: :destroy_async
  has_many :erp_order_costs, class_name: 'Erp::OrderCost', dependent: :destroy_async
  has_many :erp_bom_costs, class_name: 'Erp::BomCost', dependent: :destroy_async
  has_many :erp_voucher_templates, class_name: 'Erp::VoucherTemplate', dependent: :destroy_async
  has_many :erp_expense_payouts, class_name: 'Erp::ExpensePayout', dependent: :destroy_async
  has_many :mes_suppliers, class_name: 'Mes::Supplier', dependent: :destroy_async
  has_many :mes_warehouses, class_name: 'Mes::Warehouse', dependent: :destroy_async
  has_many :mes_materials, class_name: 'Mes::Material', dependent: :destroy_async
  has_many :crm_issue_reports, dependent: :destroy_async, class_name: 'Crm::IssueReport'
  has_many :mes_material_prices, dependent: :destroy_async, class_name: 'Mes::MaterialPrice'
  has_many :mes_boms, class_name: 'Mes::Bom', dependent: :destroy_async
  has_many :mes_bom_items, class_name: 'Mes::BomItem', dependent: :destroy_async
  has_many :mes_purchase_orders, class_name: 'Mes::PurchaseOrder', dependent: :destroy_async
  has_many :mes_purchase_items, class_name: 'Mes::PurchaseItem', dependent: :destroy_async
  has_many :mes_purchase_requisitions, class_name: 'Mes::PurchaseRequisition', dependent: :destroy_async
  has_many :mes_purchase_requisition_items, class_name: 'Mes::PurchaseRequisitionItem', dependent: :destroy_async
  has_many :mes_bom_revisions, class_name: 'Mes::BomRevision', dependent: :destroy_async
  has_many :mes_stock_entries, class_name: 'Mes::StockEntry', dependent: :destroy_async
  has_many :mes_stock_entry_items, class_name: 'Mes::StockEntryItem', dependent: :destroy_async
  has_many :mes_stock_ledgers, class_name: 'Mes::StockLedger', dependent: :destroy_async
  has_many :mes_stock_balances, class_name: 'Mes::StockBalance', dependent: :destroy_async
  has_many :mes_production_records, class_name: 'Mes::ProductionRecord', dependent: :destroy_async
  has_many :mes_production_order_stage_events, class_name: 'Mes::ProductionOrderStageEvent', dependent: :destroy_async
  has_many :mes_inspections, class_name: 'Mes::Inspection', dependent: :destroy_async
  has_many :mes_serial_numbers, class_name: 'Mes::SerialNumber', dependent: :destroy_async
  has_many :mes_shipments, class_name: 'Mes::Shipment', dependent: :destroy_async
  has_many :mes_shipment_items, class_name: 'Mes::ShipmentItem', dependent: :destroy_async
  has_many :mes_production_orders, class_name: 'Mes::ProductionOrder', dependent: :destroy_async
  has_many :mes_order_feedbacks, class_name: 'Mes::OrderFeedback', dependent: :destroy_async
  has_many :mes_supplier_returns, class_name: 'Mes::SupplierReturn', dependent: :destroy_async
  has_many :mes_board_owners, class_name: 'Mes::BoardOwner', dependent: :destroy_async
  has_many :mes_bom_templates, class_name: 'Mes::BomTemplate', dependent: :destroy_async
  has_many :mes_notifications, class_name: 'Mes::Notification', dependent: :destroy_async
  has_many :mes_order_forwards, class_name: 'Mes::OrderForward', dependent: :destroy_async
  has_many :org_departments, class_name: 'Org::Department', dependent: :destroy_async
  has_many :org_memberships, class_name: 'Org::Membership', dependent: :destroy_async
  has_many :oa_approval_templates, class_name: 'Oa::ApprovalTemplate', dependent: :destroy_async
  has_many :oa_approval_requests, class_name: 'Oa::ApprovalRequest', dependent: :destroy_async
  has_many :chat_conversations, class_name: 'Chat::Conversation', dependent: :destroy_async
  has_many :csat_survey_responses, dependent: :destroy_async
  has_many :custom_attribute_definitions, dependent: :destroy_async
  has_many :custom_filters, dependent: :destroy_async
  has_many :dashboard_apps, dependent: :destroy_async
  has_many :data_imports, dependent: :destroy_async
  has_many :email_channels, dependent: :destroy_async, class_name: '::Channel::Email'
  has_many :facebook_pages, dependent: :destroy_async, class_name: '::Channel::FacebookPage'
  has_many :instagram_channels, dependent: :destroy_async, class_name: '::Channel::Instagram'
  has_many :tiktok_channels, dependent: :destroy_async, class_name: '::Channel::Tiktok'
  has_many :hooks, dependent: :destroy_async, class_name: 'Integrations::Hook'
  has_many :inboxes, dependent: :destroy_async
  has_many :labels, dependent: :destroy_async
  has_many :line_channels, dependent: :destroy_async, class_name: '::Channel::Line'
  has_many :mentions, dependent: :destroy_async
  has_many :messages, dependent: :destroy_async
  has_many :notes, dependent: :destroy_async
  has_many :notification_settings, dependent: :destroy_async
  has_many :notifications, dependent: :destroy_async
  has_many :portals, dependent: :destroy_async, class_name: '::Portal'
  has_many :sms_channels, dependent: :destroy_async, class_name: '::Channel::Sms'
  has_many :teams, dependent: :destroy_async
  has_many :telegram_channels, dependent: :destroy_async, class_name: '::Channel::Telegram'
  has_many :twilio_sms, dependent: :destroy_async, class_name: '::Channel::TwilioSms'
  has_many :twitter_profiles, dependent: :destroy_async, class_name: '::Channel::TwitterProfile'
  has_many :users, through: :account_users
  has_many :web_widgets, dependent: :destroy_async, class_name: '::Channel::WebWidget'
  has_many :webhooks, dependent: :destroy_async
  has_many :whatsapp_channels, dependent: :destroy_async, class_name: '::Channel::Whatsapp'
  has_many :whatsapp_web_channels, dependent: :destroy_async, class_name: '::Channel::WhatsappWeb'
  has_many :working_hours, dependent: :destroy_async

  has_one_attached :contacts_export

  enum :locale, LANGUAGES_CONFIG.map { |key, val| [val[:iso_639_1_code], key] }.to_h, prefix: true
  enum :status, { active: 0, suspended: 1 }

  scope :with_auto_resolve, -> { where("(settings ->> 'auto_resolve_after')::int IS NOT NULL") }

  before_validation :validate_limit_keys
  after_create_commit :notify_creation
  after_update_commit :clear_unread_conversation_counts_cache, if: :saved_change_to_feature_conversation_unread_counts?
  after_destroy :remove_account_sequences

  def agents
    users.where(account_users: { role: :agent })
  end

  def administrators
    users.where(account_users: { role: :administrator })
  end

  def all_conversation_tags
    # returns array of tags
    conversation_ids = conversations.pluck(:id)
    ActsAsTaggableOn::Tagging.includes(:tag)
                             .where(context: 'labels',
                                    taggable_type: 'Conversation',
                                    taggable_id: conversation_ids)
                             .map { |tagging| tagging.tag.name }
  end

  def webhook_data
    {
      id: id,
      name: name
    }
  end

  def inbound_email_domain
    domain.presence || GlobalConfig.get('MAILER_INBOUND_EMAIL_DOMAIN')['MAILER_INBOUND_EMAIL_DOMAIN'] || ENV.fetch('MAILER_INBOUND_EMAIL_DOMAIN',
                                                                                                                   false)
  end

  def support_email
    super.presence || ENV.fetch('MAILER_SENDER_EMAIL') { GlobalConfig.get('MAILER_SUPPORT_EMAIL')['MAILER_SUPPORT_EMAIL'] }
  end

  def usage_limits
    {
      agents: ChatwootApp.max_limit.to_i,
      inboxes: ChatwootApp.max_limit.to_i
    }
  end

  def locale_english_name
    # the locale can also be something like pt_BR, en_US, fr_FR, etc.
    # the format is `<locale_code>_<country_code>`
    # we need to extract the language code from the locale
    account_locale = locale&.split('_')&.first
    ISO_639.find(account_locale)&.english_name&.downcase || 'english'
  end

  def onboarding_step
    step = custom_attributes['onboarding_step']
    return nil if step.blank?

    enrichment_key = format(Redis::Alfred::ACCOUNT_ONBOARDING_ENRICHMENT, account_id: id)
    Redis::Alfred.exists?(enrichment_key) ? 'enrichment' : step
  end

  def reset_cache_keys
    super
    clear_unread_conversation_counts_cache
  end

  private

  def notify_creation
    Rails.configuration.dispatcher.dispatch(ACCOUNT_CREATED, Time.zone.now, account: self)
  end

  def clear_unread_conversation_counts_cache
    ::Conversations::UnreadCounts::Store.clear_account!(id)
  end

  trigger.after(:insert).for_each(:row) do
    "execute format('create sequence IF NOT EXISTS conv_dpid_seq_%s', NEW.id);"
  end

  trigger.name('camp_dpid_before_insert').after(:insert).for_each(:row) do
    "execute format('create sequence IF NOT EXISTS camp_dpid_seq_%s', NEW.id);"
  end

  def validate_limit_keys
    # method overridden in enterprise module
  end

  def validate_reporting_timezone
    return if reporting_timezone.blank? || ActiveSupport::TimeZone[reporting_timezone].present?

    errors.add(:reporting_timezone, I18n.t('errors.account.reporting_timezone.invalid'))
  end

  def validate_support_email_format
    value = attributes['support_email']
    return if value.blank?

    parsed = Mail::Address.new(value).address
    errors.add(:support_email, I18n.t('errors.account.support_email.invalid')) if parsed.blank?
  rescue Mail::Field::ParseError, Mail::Field::IncompleteParseError
    errors.add(:support_email, I18n.t('errors.account.support_email.invalid'))
  end

  def remove_account_sequences
    ActiveRecord::Base.connection.exec_query("drop sequence IF EXISTS camp_dpid_seq_#{id}")
    ActiveRecord::Base.connection.exec_query("drop sequence IF EXISTS conv_dpid_seq_#{id}")
  end
end

Account.prepend_mod_with('Account')
Account.prepend_mod_with('Account::PlanUsageAndLimits')
Account.include_mod_with('Concerns::Account')
Account.include_mod_with('Audit::Account')
