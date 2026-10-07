Rails.application.routes.draw do
  # AUTH STARTS
  mount_devise_token_auth_for 'User', at: 'auth', controllers: {
    confirmations: 'devise_overrides/confirmations',
    passwords: 'devise_overrides/passwords',
    sessions: 'devise_overrides/sessions',
    token_validations: 'devise_overrides/token_validations',
    omniauth_callbacks: 'devise_overrides/omniauth_callbacks'
  }, via: [:get, :post]

  post 'resend_confirmation', to: 'auth/resend_confirmations#create'

  # 企业微信工作台免密登录（无需登录态）
  get 'wecom/enter', to: 'wecom_oauth#enter'
  get 'wecom/callback', to: 'wecom_oauth#callback'

  ## renders the frontend paths only if its not an api only server
  if ActiveModel::Type::Boolean.new.cast(ENV.fetch('CW_API_ONLY_SERVER', false))
    root to: 'api#index'
  else
    root to: 'dashboard#index'

    get '/app', to: 'dashboard#index'
    get '/app/*params', to: 'dashboard#index'
    get '/app/accounts/:account_id/settings/inboxes/new/twitter', to: 'dashboard#index', as: 'app_new_twitter_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/microsoft', to: 'dashboard#index', as: 'app_new_microsoft_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/instagram', to: 'dashboard#index', as: 'app_new_instagram_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/tiktok', to: 'dashboard#index', as: 'app_new_tiktok_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_twitter_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_email_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_instagram_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_tiktok_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/:inbox_id', to: 'dashboard#index', as: 'app_instagram_inbox_settings'
    get '/app/accounts/:account_id/settings/inboxes/:inbox_id', to: 'dashboard#index', as: 'app_tiktok_inbox_settings'
    get '/app/accounts/:account_id/settings/inboxes/:inbox_id', to: 'dashboard#index', as: 'app_email_inbox_settings'
    get '/app/accounts/:account_id/onboarding/inbox-setup', to: 'dashboard#index', as: 'app_onboarding_inbox_setup'

    resource :widget, only: [:show]
    namespace :survey do
      resources :responses, only: [:show]
    end
    resource :slack_uploads, only: [:show]
  end

  get '/health', to: 'health#show'
  get '/api', to: 'api#index'
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      # ----------------------------------
      # start of account scoped api routes
      resources :accounts, only: [:create, :show, :update] do
        member do
          post :update_active_at
          get :cache_keys
        end

        scope module: :accounts do
          namespace :actions do
            resource :contact_merge, only: [:create]
          end
          namespace :crm do
            resources :customers do
              collection do
                get :check_duplicate
                get :duplicates
                get :dedupe_search
                get :identify
                get :churn_risk_count
                get :stats
                # 历史 PI 附件盘点：找出传在客户「文件」页、没走销售订单的 PI
                get :pi_attachment_candidates
                post :reassign
                post :bulk_update
                post :import
              end
              member do
                get :audits
                get :detail
                post :claim
                post :release
                post :share
                post :attach
                # 会话右侧的客户卡片（轻量，不走 detail）
                get :card
                # 互动时间线：跟进/邮件/会话/订单合流
                get :timeline
                # 就地识别客户附件里的 PI（前端据此开建单弹窗）
                post :parse_attachment
                post :attach_contact
                post :merge
                delete 'attach/:attachment_id', action: :detach
                post :favorite
                delete :favorite, action: :unfavorite
                post :schedule_follow_up
              end
            end
            resources :contacts, only: [:index, :update]
            resources :option_items, only: [:index, :create, :update, :destroy] do
              collection do
                post :reorder
              end
            end
            resources :opportunities
            # 展会邀约获客：展会 + 匹配潜客 + 加入名单；邀约记录的邀请函生成/阶段流转。
            resources :exhibitions do
              member do
                get :candidates
                post :add_invites
                get :apollo_search
                post :add_apollo_invites
                post :generate_sop_drafts
              end
            end
            resources :exhibition_invites, only: [:destroy] do
              member do
                post :compose
                post :advance
              end
            end
            resources :products
            resources :pis do
              collection do
                get :prefill
                get :company_headers
                get :summary
                post :parse_pi
              end
              member do
                get :xlsx
                get :preview
              end
            end
            resource :pi_seller_profile, only: [:show, :update], controller: 'pi_seller_profiles'
            resources :recipient_suggestions, only: [:index]
            resources :agents, only: [:index]
            resources :quick_texts, only: [:index, :create, :update, :destroy]
            resources :schedule_events, only: [:index, :create, :update, :destroy] do
              member do
                post :toggle_done
                post :complete_follow_up
              end
              collection { get :pending_count }
            end
            get 'home_stats', to: 'home_stats#index'
            resources :sales_orders do
              collection do
                post :parse_pi
                get :deleted
              end
              member do
                get :audits
                get :convert_preview
                get :receivable_progress
                get :production_trace
                get :erp_export
                post :attach
                delete 'attach/:attachment_id', action: :detach
                post :restore
              end
            end
            resources :commission_sheets do
              collection do
                post :mark_paid
                post :unmark_paid
                get :rates
                post :save_rates
              end
              member do
                post :pull_orders
                post :submit
                post :approve
                post :return_sheet
                get :xlsx
                get :selectable_orders
                post :import_orders
              end
            end
            # 备用金台账：一个部门/项目一本账，本下挂收支流水。
            resources :petty_cash_books, only: [:index, :create, :update, :destroy] do
              resources :petty_cash_entries, only: [:index, :create, :update, :destroy]
            end
            # 核价表（内部报价单）：按版本维护，业务员只读已发布版并可导出 PDF。
            resources :price_lists do
              collection do
                post :import
                # 公司文档里的图片清单，供核价表挑产品图
                get :doc_images
                # 跨产品线搜型号
                get :search
              end
              member do
                post :publish
                post :duplicate
                get :export_pdf
                get :diff
                post 'items/:item_id/image', action: :upload_image
                post 'items/:item_id/image_from_doc', action: :image_from_doc
                delete 'items/:item_id/image', action: :remove_image
              end
            end
            # 邮件 AI 助手：写信 / 翻译 / 往来摘要（同步生成，前端等待）。
            post 'ai/compose', to: 'ai#compose'
            post 'ai/translate', to: 'ai#translate'
            post 'ai/summarize', to: 'ai#summarize'
            # 会话自动翻译：保存会话级开关/对方语言 + 外发中文译成对方语言。
            patch 'conversation_translation/:conversation_id/settings', to: 'conversation_translation#settings'
            post 'conversation_translation/:conversation_id/translate', to: 'conversation_translation#translate'
            post 'ai/suggest', to: 'ai#suggest'
            post 'ai/ask', to: 'ai#ask'
            # 客服分配设置：管理收件箱协作者（会话「分配客服代表」可选的人）。
            get 'inbox_collaborators', to: 'inbox_collaborators#index'
            patch 'inbox_collaborators', to: 'inbox_collaborators#update'
            # 客户 AI 背调：输入邮箱/域名/网址→抓官网 + Apollo 概况；公司名先搜候选。
            post 'ai/company_lookup', to: 'ai#company_lookup'
            post 'ai/company_search', to: 'ai#company_search'
            # 会话「来源」标签(复用客户来源选项),打在会话上,会话卡显示彩色胶囊。
            patch 'conversation_source_tags/:conversation_id', to: 'conversation_source_tags#update'
            # 侧栏「客户来源」分组的会话数角标
            get 'conversation_source_tags/counts', to: 'conversation_source_tags#counts'
            # 业务员个人 WhatsApp 号(WhatsApp Web/Baileys)绑定：支持一人多号,按 inbox 扫码/状态/解绑。
            get 'whatsapp_web', to: 'whatsapp_web#index'
            post 'whatsapp_web', to: 'whatsapp_web#create'
            post 'whatsapp_web/:inbox_id/connect', to: 'whatsapp_web#connect'
            post 'whatsapp_web/:inbox_id/start_chat', to: 'whatsapp_web#start_chat'
            get 'whatsapp_web/:inbox_id/status', to: 'whatsapp_web#status'
            delete 'whatsapp_web/:inbox_id', to: 'whatsapp_web#logout'
            resources :emails do
              collection do
                get :counts
                get :mailboxes
                post :fetch
                post :move_to_folder
                post :bulk_create
                get :distributed
                get :distributed_by_me
                get :forced_cc
              end
              member do
                post :attach_kb
                get :opens
                get :eml
                get :thread
                post :distribute
                get :distributions
              end
            end
            resources :email_folders, only: [:index, :create, :destroy]
            resources :email_labels, only: [:index, :create, :update, :destroy]
            resources :quotes do
              resources :line_items, only: [:index, :create], controller: 'quote_line_items'
              collection do
                get :prefill
                get :summary
              end
              member do
                get :xlsx
                get :preview
                post :convert_to_sales_order
              end
            end
            resources :quote_line_items, only: [:update, :destroy]
            resources :email_signatures
            resources :follow_up_notes
            resources :follow_up_tasks
            resources :knowledge_docs do
              collection do
                get :recycle_bin
                post :purge_all
                post :snapshot_files
              end
              member do
                get :audits
                post :attach
                delete 'attach/:attachment_id', action: :detach
                post :restore
                post :purge
              end
            end
            resources :knowledge_categories, only: [:index, :create, :update, :destroy]
            resources :teams
            resources :sales_targets
            resource :public_pool_settings, only: [:show, :update]
            resource :ai_settings, only: [:show, :update], controller: 'ai_settings'
            post 'ai_settings/test', to: 'ai_settings#test'
            resources :doc_sections, only: [:index, :create, :update, :destroy]
            resources :credentials, only: [:index, :create, :update, :destroy] do
              member { post :reveal }
              collection { get :views }
            end
            resources :credential_groups, only: [:create, :update, :destroy]
            resource :stats, only: [:show], controller: 'stats'
            resource :team_dashboard, only: [:show], controller: 'team_dashboard'
            resource :my_target, only: [:show], controller: 'my_target'
            resource :signature, only: [:show, :create, :destroy], controller: 'signatures'
            resources :mail_accounts do
              member { post :test }
            end
            resources :email_templates
            resources :members, only: [:index, :create, :update, :destroy] do
              member do
                post :deactivate
                post :reactivate
              end
            end
            resources :member_invites, only: [:index, :create, :destroy]
            resources :role_templates, only: [:index, :create, :update, :destroy]
            resources :kpi_schemes do
              member do
                post :distribute
                post :duplicate
              end
            end
            resources :kpi_sheets do
              member do
                post :submit
                post :score
                post :hr_confirm
                post :gm_confirm
                post :ai_suggest
                post :return_sheet
                post :reopen_scoring
              end
            end
            resources :employee_comps
            resources :employees do
              member do
                get :audits
                post :attach
                delete 'attach/:attachment_id', action: :detach
              end
            end
            resource :sensitive_session, only: [:show, :create], controller: 'sensitive_sessions'
            resources :attendance_groups, only: [:index, :create, :update, :destroy]
            resources :attendances, only: [:index] do
              collection do
                post :clock
                get :summary
                get :export
                get :user_summary
                post :adjust
                get :my_network
              end
            end
            # 定制报价：业务员按产品线模板填参数,主管(或被转交的人)填价格回来。
            resources :quote_request_templates, only: [:index, :create, :update, :destroy]
            resources :quote_requests, only: [:index, :show, :create] do
              collection { get :templates }
              member do
                post :quote
                post :transfer
                post :cancel
              end
            end
            resource :performance_settings, only: [:show, :update], controller: 'performance_settings'
          end
          namespace :erp do
            resource :dashboard, only: [:show], controller: 'dashboard'
            resource :settings, only: [:show, :update], controller: 'settings'
            resources :ledger_accounts, only: [:index, :show, :create, :update, :destroy] do
              collection do
                post :initialize_standard
                get :inventory_map
                put :update_inventory_map
              end
            end
            resources :voucher_templates, only: [:index, :create, :destroy]
            resources :vouchers, only: [:index, :show, :create, :update, :destroy] do
              collection do
                get :summaries
                get :import_template
                post :import
              end
              member do
                post :post_voucher
                post :reverse
                post :void
                post :attach
                delete :detach
              end
            end
            # 账簿：余额表 / 明细账 / 维度明细账（只读实时查询）
            get 'ledgers/balances', to: 'ledgers#balances'
            get 'ledgers/entries', to: 'ledgers#entries'
            get 'ledgers/dimensions', to: 'ledgers#dimensions'
            resources :receivables, only: [:index, :show, :create, :update, :destroy] do
              collection do
                get :open_list
                get :aging
                get :pending_orders
                get :order_detail
                post :bulk_build
              end
            end
            resources :receipt_records, only: [:index, :show, :create, :update, :destroy] do
              member { post :void }
            end
            resources :payables, only: [:index, :show, :create, :update, :destroy] do
              collection do
                get :open_list
                get :supplier_statement
                get :aging
              end
            end
            resources :payment_records, only: [:index, :show, :create, :update, :destroy] do
              member { post :void }
            end
            # 费用报销打款（承接 OA 审批通过后的财务动作）
            resources :expense_payouts, only: [:index, :show, :create, :update] do
              collection { get :pending }
              member { post :void }
            end
            resources :cash_accounts, only: [:index, :show, :create, :update, :destroy] do
              collection do
                get :transactions
                get :report
                post :transfer
              end
            end
            resources :auto_voucher_rules, only: [:index, :update]
            resources :stock_layers, only: [:index] do
              collection do
                post :import
                get :import_template
              end
            end
            resources :order_costs, only: [:index, :create, :update, :destroy] do
              collection do
                get :margin
                post :rollup
              end
            end
            resources :fixed_assets, only: [:index, :show, :create, :update, :destroy] do
              collection { post :depreciate }
              member { post :dispose }
            end
            resources :fiscal_periods, only: [:index] do
              collection do
                post :close
                post :reopen
                get :opening_balance
                post :save_opening_balance
                get :reconciliation
                get :revaluation
                post :revalue
                get :bad_debt
                post :provision_bad_debt
                get :year_end
                post :close_year
                post :reopen_year
              end
            end
            # 财务报表：资产负债表（时点）/ 利润表（期间）/ 现金流量表（期间）
            get 'reports/balance_sheet', to: 'reports#balance_sheet'
            get 'reports/income_statement', to: 'reports#income_statement'
            get 'reports/cash_flow', to: 'reports#cash_flow'
            get 'reports/cash_flow_items', to: 'reports#cash_flow_items'
            get 'reports/account_balances', to: 'reports#account_balances'
            get 'reports/trial_balance', to: 'reports#trial_balance'
            get 'reports/tie_check', to: 'reports#tie_check'
            get 'reports/audit_export', to: 'reports#audit_export'
          end
          namespace :mes do
            resource :dashboard, only: [:show], controller: 'dashboard' do
              get :pipeline
            end
            resources :board_owners, only: [:index] do
              put :set, on: :collection
            end
            resources :notifications, only: [:index] do
              collection do
                get :unread_count
                post :mark_all_read
              end
              member { post :mark_read }
            end
            resources :suppliers
            resources :warehouses, except: [:show]
            resources :materials
            resources :products, only: [:index, :create, :update, :destroy] do
              collection do
                get :categories
                post :reorder_categories
                post :lookup
              end
              # 辅助属性：同一物料编码下的可选变体，开单时单选其一
              resources :aux_attributes, only: [:index, :create, :update, :destroy],
                                         controller: 'product_aux_attributes'
            end
            resources :product_groups, only: [:index, :create, :update, :destroy] do
              collection { post :reorder }
            end
            resources :boms do
              collection { post :stage_blob }
              member do
                post :release
                post :attach
                delete 'attach/:attachment_id', action: :detach
              end
            end
            resources :bom_templates, except: [:new, :edit]
            resources :purchase_orders do
              collection do
                get :requirement
                get :approval_inbox
              end
              member do
                post :submit
                post :approve
                post :reject
                post :return_document
                post :reactivate
                get :export
                get :export_data
                post :mark_exported
              end
            end
            resources :purchase_requisitions do
              member do
                post :submit
                post :cancel
                post :convert
              end
            end
            resources :stock_entries do
              member do
                post :post
                post :confirm_warehouse
                post :cancel
                post :return_document
                post :reactivate
              end
              collection { post :stage_blob }
            end
            resources :stock_balances, only: [:index]
            # 期初库存导入（上线前把仓库里的实物库存搬进来，见 Mes::StockOpeningImportService）
            resources :stock_openings, only: [:create] do
              post :preview, on: :collection
            end
            resources :production_records, only: [:index, :create, :destroy] do
              member do
                post :return_document
                post :reactivate
              end
            end
            resources :inspections, only: [:index, :create, :destroy] do
              collection { post :stage_blob }
            end
            resources :serial_numbers, only: [:index, :create, :destroy] do
              collection { get :trace }
            end
            resources :shipments do
              collection do
                get :approval_inbox
                post :convert
              end
              member do
                post :notify
                post :submit
                post :approve
                post :reject
                post :ship
              end
            end
            resources :production_orders do
              collection do
                post :convert
                get :inbox
                get :approval_inbox
                get :todo_count
                post :stage_blob
              end
              member do
                get :audits
                post :forward
                post :attach
                delete 'attach/:attachment_id', action: :detach
                post :attach_bom
                post :detach_bom
                post :revert_to_bom_ready
                post :release_purchasing
                post :mark_outsourced
                get :requirement
                get :issue_plan
                post :acknowledge
                post :handoff
                post :reject
                post :submit_approval
                post :approve
                post :deny
                post :set_product_code
              end
            end
          end
          namespace :org do
            resources :departments, only: [:index, :create, :update, :destroy] do
              post :reorder, on: :collection
            end
            resources :memberships, only: [:index, :create, :update, :destroy]
          end
          namespace :oa do
            resources :approval_templates, only: [:index, :create, :update, :destroy]
            resources :approval_requests, only: [:index, :show, :create, :update] do
              collection { get :counts }
              member do
                post :approve
                post :reject
                post :cancel
                post :revoke
              end
            end
          end
          namespace :chat do
            resources :conversations, only: [:index, :show, :create, :update] do
              collection do
                get :unread_total
              end
              member do
                post :read
                post :remove_participant
                post :transfer_owner
                post :leave
              end
              resources :messages, only: [:index, :create] do
                post :forward, on: :collection
              end
            end
          end
          resource :bulk_actions, only: [:create]
          resource :onboarding, only: [:update] do
            get :help_center_generation
          end
          resources :agents, only: [:index, :create, :update, :destroy] do
            post :bulk_create, on: :collection
          end
          namespace :captain do
            resource :preferences, only: [:show, :update]
            resources :assistants do
              member do
                post :playground
              end
              collection do
                get :tools
              end
              resources :inboxes, only: [:index, :create, :destroy], param: :inbox_id
              resources :scenarios
            end
            resources :assistant_responses
            resources :message_reports, only: [:create]
            resources :bulk_actions, only: [:create]
            resources :copilot_threads, only: [:index, :create] do
              resources :copilot_messages, only: [:index, :create]
            end
            resources :custom_tools do
              post :test, on: :collection
            end
            resources :documents, only: [:index, :show, :create, :destroy] do
              post :sync, on: :member
            end
            resource :tasks, only: [], controller: 'tasks' do
              post :rewrite
              post :summarize
              post :reply_suggestion
              post :label_suggestion
              post :follow_up
            end
          end
          resource :saml_settings, only: [:show, :create, :update, :destroy]
          resources :agent_bots, only: [:index, :create, :show, :update, :destroy] do
            delete :avatar, on: :member
            post :reset_access_token, on: :member
            post :reset_secret, on: :member
          end
          resources :contact_inboxes, only: [] do
            collection do
              post :filter
            end
          end
          resources :assignable_agents, only: [:index]
          resource :audit_logs, only: [:show]
          resources :callbacks, only: [] do
            collection do
              post :register_facebook_page
              get :register_facebook_page
              post :facebook_pages
              post :reauthorize_page
            end
          end
          resources :canned_responses, only: [:index, :create, :update, :destroy]
          resources :automation_rules, only: [:index, :create, :show, :update, :destroy] do
            post :clone
          end
          resources :macros, only: [:index, :create, :show, :update, :destroy] do
            post :execute, on: :member
          end
          resources :sla_policies, only: [:index, :create, :show, :update, :destroy]
          resources :custom_roles, only: [:index, :create, :show, :update, :destroy]
          resources :agent_capacity_policies, only: [:index, :create, :show, :update, :destroy] do
            scope module: :agent_capacity_policies do
              resources :users, only: [:index, :create, :destroy]
              resources :inbox_limits, only: [:create, :update, :destroy]
            end
          end
          resources :campaigns, only: [:index, :create, :show, :update, :destroy]
          resources :dashboard_apps, only: [:index, :show, :create, :update, :destroy]
          namespace :channels do
            resource :twilio_channel, only: [:create]
          end
          resources :conversations, only: [:index, :create, :show, :update, :destroy] do
            collection do
              get :meta
              get :search
              get :unread_counts, to: 'conversations/unread_counts#index'
              # 侧栏「会话 / 未处理」角标用（未处理数 + 该动手的会话数）
              get :attention_counts, to: 'conversations/attention_counts#index'
              post :filter
            end
            scope module: :conversations do
              resources :messages, only: [:index, :create, :destroy, :update] do
                member do
                  post :translate
                  post :retry
                end
              end
              resources :assignments, only: [:create]
              resources :labels, only: [:create, :index]
              resource :participants, only: [:show, :create, :update, :destroy]
              resource :direct_uploads, only: [:create]
              resource :draft_messages, only: [:show, :update, :destroy]
              # 置顶/取消置顶（每人钉自己的，见 ConversationPin）
              resource :pin, only: [:create, :destroy], controller: 'pins'
            end
            member do
              post :mute
              post :unmute
              post :transcript
              post :toggle_status
              post :toggle_priority
              post :toggle_typing_status
              post :update_last_seen
              post :unread
              post :custom_attributes
              get :attachments
              get :inbox_assistant
              get :reporting_events if ChatwootApp.enterprise?
            end
          end

          resources :search, only: [:index] do
            collection do
              get :conversations
              get :messages
              get :contacts
              get :articles
            end
          end

          resources :companies, only: [:index, :show, :create, :update, :destroy] do
            collection do
              get :search
            end
            member do
              post :destroy_custom_attributes
              delete :avatar
            end
            scope module: :companies do
              resources :contacts, only: [:index, :create, :destroy] do
                collection do
                  get :search
                end
              end
              resources :conversations, only: [:index]
              resources :notes, only: [:index]
            end
          end
          resources :contacts, only: [:index, :show, :update, :create, :destroy] do
            collection do
              get :active
              get :search
              post :filter
              post :import
              post :export
            end
            member do
              get :contactable_inboxes
              post :destroy_custom_attributes
              delete :avatar
            end
            scope module: :contacts do
              resources :conversations, only: [:index]
              resources :contact_inboxes, only: [:create]
              resources :labels, only: [:create, :index]
              resources :notes
              get :attachments, to: 'attachments#index'
              post :call, on: :member, to: 'calls#create' if ChatwootApp.enterprise?
            end
          end
          resources :csat_survey_responses, only: [:index] do
            collection do
              get :metrics
              get :download
            end
            member do
              patch :update if ChatwootApp.enterprise?
            end
          end
          resources :applied_slas, only: [:index] do
            collection do
              get :metrics
              get :download
            end
          end
          resources :reporting_events, only: [:index] if ChatwootApp.enterprise?

          if ChatwootApp.enterprise?
            resources :whatsapp_calls, only: [:show] do
              member do
                post :accept
                post :reject
                post :terminate
                post :upload_recording
              end
              collection do
                post :initiate
              end
            end
          end

          resources :custom_attribute_definitions, only: [:index, :show, :create, :update, :destroy]
          resources :custom_filters, only: [:index, :show, :create, :update, :destroy]
          resources :inboxes, only: [:index, :show, :create, :update, :destroy] do
            get :assignable_agents, on: :member
            get :campaigns, on: :member
            get :agent_bot, on: :member
            post :set_agent_bot, on: :member
            delete :avatar, on: :member
            post :sync_templates, on: :member
            get :health, on: :member
            post :register_webhook, on: :member
            post :reset_secret, on: :member
            if ChatwootApp.enterprise?
              resource :conference, only: %i[create destroy], controller: 'conference' do
                get :token, on: :member
              end
              post :enable_whatsapp_calling, on: :member
              post :disable_whatsapp_calling, on: :member
              post :set_inbound_calls, on: :member
            end

            resource :csat_template, only: [:show, :create], controller: 'inbox_csat_templates' do
              post :analyze, on: :collection
            end
          end

          resources :inbox_members, only: [:create, :show], param: :inbox_id do
            collection do
              delete :destroy
              patch :update
            end
          end
          resources :labels, only: [:index, :show, :create, :update, :destroy]

          resources :notifications, only: [:index, :update, :destroy] do
            collection do
              post :read_all
              get :unread_count
              post :destroy_all
            end
            member do
              post :snooze
              post :unread
            end
          end
          resource :notification_settings, only: [:show, :update]

          resources :teams do
            resources :team_members, only: [:index, :create] do
              collection do
                delete :destroy
                patch :update
              end
            end
          end

          # Assignment V2 Routes
          resources :assignment_policies do
            resources :inboxes, only: [:index, :create, :destroy], module: :assignment_policies
          end

          resources :inboxes, only: [] do
            resource :assignment_policy, only: [:show, :create, :destroy], module: :inboxes
          end

          namespace :twitter do
            resource :authorization, only: [:create]
          end

          namespace :microsoft do
            resource :authorization, only: [:create]
          end

          namespace :google do
            resource :authorization, only: [:create]
          end

          namespace :instagram do
            resource :authorization, only: [:create]
          end

          namespace :tiktok do
            resource :authorization, only: [:create]
            # TikTok 板块（店铺经营）：今日速览 / 看板 / 每日录入 / 利润统计 / 店铺设置 / 部门管理
            resource :dashboard, only: [:show], controller: 'dashboard'
            get 'today', to: 'dashboard#today'
            resources :departments, only: [:index, :create, :update, :destroy]
            resources :shops, only: [:index, :create, :update, :destroy]
            resources :sales_records, only: [:index, :create, :update, :destroy]
            resources :profit_records, only: [:index, :create, :update, :destroy]
            # 支出台账（按部门收口，店铺选填）+ 固定资产登记（只登记不折旧）
            resources :expenses, only: [:index, :create, :update, :destroy]
            resources :assets, only: [:index, :create, :update, :destroy]
          end

          namespace :notion do
            resource :authorization, only: [:create]
          end

          namespace :whatsapp do
            resource :authorization, only: [:create]
          end

          resources :webhooks, only: [:index, :create, :update, :destroy]
          namespace :integrations do
            resources :apps, only: [:index, :show]
            resources :hooks, only: [:show, :create, :update, :destroy] do
              member do
                post :process_event
              end
            end
            resource :slack, only: [:create, :update, :destroy], controller: 'slack' do
              member do
                get :list_all_channels
              end
            end
            resource :dyte, controller: 'dyte', only: [] do
              collection do
                post :create_a_meeting
                post :add_participant_to_meeting
              end
            end
            resource :shopify, controller: 'shopify', only: [:destroy] do
              collection do
                post :auth
                get :orders
              end
            end
            resource :linear, controller: 'linear', only: [] do
              collection do
                delete :destroy
                get :teams
                get :team_entities
                post :create_issue
                post :link_issue
                post :unlink_issue
                get :search_issue
                get :linked_issues
              end
            end
            resource :notion, controller: 'notion', only: [] do
              collection do
                delete :destroy
              end
            end
          end
          resources :portals do
            member do
              patch :archive
              delete :logo
              post :send_instructions
              get :ssl_status
            end
            resources :categories do
              post :reorder, on: :collection
            end
            namespace :articles do
              resource :bulk_actions, only: [] do
                post :translate
                patch :update_status
                patch :update_category
                delete :delete_articles
              end
            end
            resources :articles do
              post :reorder, on: :collection
            end
          end

          resources :upload, only: [:create]
        end
      end
      # end of account scoped api routes
      # ----------------------------------

      namespace :integrations do
        resources :webhooks, only: [:create]
      end

      # Frontend API endpoint to trigger SAML authentication flow
      post 'auth/saml_login', to: 'auth#saml_login'

      resource :profile, only: [:show, :update] do
        delete :avatar, on: :collection
        member do
          post :availability
          post :auto_offline
          put :set_active_account
          post :resend_confirmation
          post :reset_access_token
        end

        # MFA routes
        scope module: 'profile' do
          resource :mfa, controller: 'mfa', only: [:show, :create, :destroy] do
            post :verify
            post :backup_codes
          end
          resources :sessions, only: [:index, :destroy]
        end
      end

      resource :notification_subscriptions, only: [:create, :destroy]

      namespace :widget do
        resource :direct_uploads, only: [:create]
        resource :config, only: [:create]
        resources :campaigns, only: [:index]
        resources :events, only: [:create]
        resources :messages, only: [:index, :create, :update]
        resources :conversations, only: [:index, :create] do
          collection do
            post :destroy_custom_attributes
            post :set_custom_attributes
            post :update_last_seen
            post :toggle_typing
            post :transcript
            get  :toggle_status
          end
        end
        resource :contact, only: [:show, :update] do
          collection do
            post :destroy_custom_attributes
            patch :set_user
          end
        end
        resources :inbox_members, only: [:index]
        resources :labels, only: [:create, :destroy]
        namespace :integrations do
          resource :dyte, controller: 'dyte', only: [] do
            collection do
              post :add_participant_to_meeting
            end
          end
        end
      end
    end

    namespace :v2 do
      resources :accounts, only: [:create] do
        scope module: :accounts do
          resources :summary_reports, only: [] do
            collection do
              get :agent
              get :team
              get :inbox
              get :label
              get :channel
            end
          end
          resources :reports, only: [:index] do
            collection do
              get :summary
              get :bot_summary
              get :agents
              get :inboxes
              get :labels
              get :teams
              get :conversations
              get :conversations_summary
              get :conversation_traffic
              get :bot_metrics
              get :inbox_label_matrix
              get :first_response_time_distribution
              get :outgoing_messages_count
            end
          end
          resource :year_in_review, only: [:show]
          resources :live_reports, only: [] do
            collection do
              get :conversation_metrics
              get :grouped_conversation_metrics
            end
          end
        end
      end
    end
  end

  if ChatwootApp.enterprise?
    namespace :enterprise, defaults: { format: 'json' } do
      namespace :api do
        namespace :v1 do
          resources :accounts do
            member do
              post :checkout
              post :subscription
              get :limits
              post :toggle_deletion
              post :topup_checkout
            end
          end
        end
      end

      post 'webhooks/stripe', to: 'webhooks/stripe#process_payload'
      post 'webhooks/firecrawl', to: 'webhooks/firecrawl#process_payload'
    end
  end

  # ----------------------------------------------------------------------
  # Routes for platform APIs
  namespace :platform, defaults: { format: 'json' } do
    namespace :api do
      namespace :v1 do
        resources :users, only: [:create, :show, :update, :destroy] do
          member do
            get :login
            post :token
          end
        end
        resources :agent_bots, only: [:index, :create, :show, :update, :destroy] do
          delete :avatar, on: :member
        end
        resources :accounts, only: [:index, :create, :show, :update, :destroy] do
          resources :account_users, only: [:index, :create] do
            collection do
              delete :destroy
            end
          end
          resources :email_channel_migrations, only: [:create]
        end
      end
    end
  end

  # ----------------------------------------------------------------------
  # Routes for inbox APIs Exposed to contacts
  namespace :public, defaults: { format: 'json' } do
    namespace :api do
      namespace :v1 do
        resources :inboxes do
          scope module: :inboxes do
            resources :contacts, only: [:create, :show, :update] do
              resources :conversations, only: [:index, :create, :show] do
                member do
                  post :toggle_status
                  post :toggle_typing
                  post :update_last_seen
                end

                resources :messages, only: [:index, :create, :update]
              end
            end
          end
        end

        resources :csat_survey, only: [:show, :update]
        # 成员邀请：凭 token 查看/加入（未登录）。
        resources :member_invites, only: [:show], param: :token do
          member { post :accept }
        end
      end
    end
  end

  get 'hc/:slug', to: 'public/api/v1/portals#show'
  get 'hc/:slug/sitemap.xml', to: 'public/api/v1/portals#sitemap'
  get 'hc/:slug/:locale', to: 'public/api/v1/portals#show', as: :public_portal_locale
  get 'hc/:slug/:locale/search', to: 'public/api/v1/portals/search#index', as: :portal_search
  get 'hc/:slug/:locale/articles', to: 'public/api/v1/portals/articles#index'
  get 'hc/:slug/:locale/categories', to: 'public/api/v1/portals/categories#index'
  get 'hc/:slug/:locale/categories/:category_slug', to: 'public/api/v1/portals/categories#show', as: :public_portal_category
  get 'hc/:slug/:locale/categories/:category_slug/articles', to: 'public/api/v1/portals/articles#index'
  get 'hc/:slug/articles/:article_slug.png', to: 'public/api/v1/portals/articles#tracking_pixel'
  get 'hc/:slug/articles/:article_slug.md', to: 'public/api/v1/portals/articles#show_markdown', as: :public_portal_article_markdown,
                                            defaults: { format: :md }
  get 'hc/:slug/articles/:article_slug', to: 'public/api/v1/portals/articles#show', as: :public_portal_article

  # ----------------------------------------------------------------------
  # Used in mailer templates
  resource :app, only: [:index] do
    resources :accounts do
      resources :conversations, only: [:show]
    end
  end

  # CRM 邮件追踪像素（公开、免登录）：收件人打开邮件加载像素即回调记录。
  get 'crm_email_open/:token', to: 'crm/email_tracking#show', constraints: { token: /[a-f0-9]+/ }
  get 'crm_email_click/:token', to: 'crm/email_tracking#click', constraints: { token: /[a-f0-9]+/ }

  # 展会邀请函落地页（公开、免登录）：客户点邀请邮件里的链接进来确认到访。
  get 'crm_exhibition_invite/:token', to: 'crm/exhibition_invites#landing', as: :crm_exhibition_invite, constraints: { token: /[a-f0-9]+/ }
  post 'crm_exhibition_invite/:token/confirm', to: 'crm/exhibition_invites#confirm', as: :confirm_crm_exhibition_invite, constraints: { token: /[a-f0-9]+/ }

  # ----------------------------------------------------------------------
  # Routes for channel integrations
  mount Facebook::Messenger::Server, at: 'bot'
  get 'webhooks/twitter', to: 'api/v1/webhooks#twitter_crc'
  post 'webhooks/twitter', to: 'api/v1/webhooks#twitter_events'
  post 'webhooks/line/:line_channel_id', to: 'webhooks/line#process_payload'
  post 'webhooks/telegram/:bot_token', to: 'webhooks/telegram#process_payload'
  post 'webhooks/sms/:phone_number', to: 'webhooks/sms#process_payload'
  get 'webhooks/whatsapp/:phone_number', to: 'webhooks/whatsapp#verify'
  post 'webhooks/whatsapp/:phone_number', to: 'webhooks/whatsapp#process_payload'
  post 'webhooks/whatsapp_web', to: 'webhooks/whatsapp_web#process_payload'
  post 'webhooks/whatsapp_web/status', to: 'webhooks/whatsapp_web#status'
  post 'webhooks/whatsapp_web/receipt', to: 'webhooks/whatsapp_web#receipt'
  post 'webhooks/whatsapp_web/history', to: 'webhooks/whatsapp_web#history'
  post 'webhooks/whatsapp_web/contacts', to: 'webhooks/whatsapp_web#contacts'
  post 'webhooks/whatsapp_web/avatar', to: 'webhooks/whatsapp_web#avatar'
  get 'webhooks/instagram', to: 'webhooks/instagram#verify'
  post 'webhooks/instagram', to: 'webhooks/instagram#events'
  post 'webhooks/tiktok', to: 'webhooks/tiktok#events'
  post 'webhooks/shopify', to: 'webhooks/shopify#events'

  namespace :twitter do
    resource :callback, only: [:show]
  end

  namespace :linear do
    resource :callback, only: [:show]
  end

  namespace :shopify do
    resource :callback, only: [:show]
  end

  namespace :twilio do
    resources :callback, only: [:create]
    resources :delivery_status, only: [:create]

    if ChatwootApp.enterprise?
      post 'voice/call/:phone', to: 'voice#call_twiml', as: :voice_call
      post 'voice/status/:phone', to: 'voice#status', as: :voice_status
      post 'voice/conference_status/:phone', to: 'voice#conference_status', as: :voice_conference_status
      post 'voice/recording_status/:phone', to: 'voice#recording_status', as: :voice_recording_status
    end
  end

  get 'microsoft/callback', to: 'microsoft/callbacks#show'
  get 'google/callback', to: 'google/callbacks#show'
  get 'instagram/callback', to: 'instagram/callbacks#show'
  get 'tiktok/callback', to: 'tiktok/callbacks#show'
  get 'notion/callback', to: 'notion/callbacks#show'
  # ----------------------------------------------------------------------
  # Routes for external service verifications
  get '.well-known/assetlinks.json' => 'android_app#assetlinks'
  get '.well-known/apple-app-site-association' => 'apple_app#site_association'
  get '.well-known/microsoft-identity-association.json' => 'microsoft#identity_association'
  get '.well-known/cf-custom-hostname-challenge/:id', to: 'custom_domains#verify'

  # ----------------------------------------------------------------------
  # Internal Monitoring Routes
  require 'sidekiq/web'
  require 'sidekiq/cron/web'

  devise_for :super_admins, path: 'super_admin', controllers: { sessions: 'super_admin/devise/sessions' }
  devise_scope :super_admin do
    get 'super_admin/logout', to: 'super_admin/devise/sessions#destroy'
    namespace :super_admin do
      root to: 'dashboard#index'

      resource :app_config, only: [:show, :create]
      resource :push_diagnostics, only: [:show, :create] do
        post :destroy_subscriptions, on: :collection
      end

      # order of resources affect the order of sidebar navigation in super admin
      resources :accounts, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
        post :seed, on: :member
        post :reset_cache, on: :member
      end
      resources :users, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
        delete :avatar, on: :member, action: :destroy_avatar
      end

      resources :access_tokens, only: [:index, :show]
      resources :installation_configs, only: [:index, :new, :create, :show, :edit, :update]
      resources :agent_bots, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
        delete :avatar, on: :member, action: :destroy_avatar
      end
      resources :platform_apps, only: [:index, :new, :create, :show, :edit, :update, :destroy]
      resources :platform_banners
      resource :instance_status, only: [:show]

      resource :settings, only: [:show] do
        get :refresh, on: :collection
      end

      # resources that doesn't appear in primary navigation in super admin
      resources :account_users, only: [:new, :create, :show, :destroy]
    end
    authenticated :super_admin do
      mount Sidekiq::Web => '/monitoring/sidekiq'
    end
  end

  namespace :installation do
    get 'onboarding', to: 'onboarding#index'
    post 'onboarding', to: 'onboarding#create'
  end

  # ---------------------------------------------------------------------
  # Routes for swagger docs
  get '/swagger/*path', to: 'swagger#respond'
  get '/swagger', to: 'swagger#respond'

  # ----------------------------------------------------------------------
  # Routes for testing
  resources :widget_tests, only: [:index] unless Rails.env.production?
end
