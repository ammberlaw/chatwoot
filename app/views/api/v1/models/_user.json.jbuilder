json.access_token resource.access_token.token
json.account_id resource.active_account_user&.account_id
json.available_name resource.available_name
json.avatar_url resource.avatar_url
json.confirmed resource.confirmed?
json.display_name resource.display_name
json.message_signature resource.message_signature
json.email resource.email
json.hmac_identifier resource.hmac_identifier if GlobalConfig.get('CHATWOOT_INBOX_HMAC_KEY')['CHATWOOT_INBOX_HMAC_KEY'].present?
json.id resource.id
json.inviter_id resource.active_account_user&.inviter_id
json.name resource.name
json.crm_name resource.crm_name
json.provider resource.provider
json.pubsub_token resource.pubsub_token
json.custom_attributes resource.custom_attributes if resource.custom_attributes.present?
json.role resource.active_account_user&.role
json.crm_role resource.active_account_user&.crm_role
# 有效主管身份（角色为主管，或副管理员/管理员兼任业务部门负责人），前端判主管一律用它
json.crm_manager resource.active_account_user&.crm_manager? || false
# 是否 CRM 团队负责人（crm_teams.team_lead_id）。销售订单按 CRM 团队收口，前端据此放行「全部」视图。
json.crm_team_lead resource.active_account_user&.crm_team_lead? || false
# 财务身份：可查看全员「已通过」提成表并导出（与业务员身份叠加）。
json.crm_finance resource.active_account_user&.crm_finance? || false
json.mes_role resource.active_account_user&.mes_role
json.mes_roles resource.active_account_user&.effective_mes_roles || []
json.mes_capabilities resource.active_account_user&.mes_capability_list || []
json.erp_role resource.active_account_user&.erp_role
json.erp_capabilities resource.active_account_user&.erp_capability_list || []
json.can_access_erp resource.active_account_user&.can_access_erp? || false
json.can_access_crm resource.active_account_user&.can_access_crm? || false
json.can_access_tiktok resource.active_account_user&.can_access_tiktok? || false
json.tiktok_can_manage(resource.active_account_user&.administrator? || resource.active_account_user&.crm_deputy_admin? || false)
json.tiktok_can_view_profit resource.active_account_user&.can_view_tiktok_profit? || false
json.module_access resource.active_account_user&.module_access || []
json.oa_template_maintainer resource.active_account_user&.oa_template_maintainer? || false
json.org_maintainer resource.active_account_user&.org_maintainer? || false
# 组织架构部门负责人：备用金台账按此放行（与 crm_manager 口径不同，勿混用）。
json.org_dept_leader resource.active_account_user&.leads_business_department? || false
json.password_self_service resource.account_users.any?(&:password_self_service?)
if (crm_au = resource.active_account_user)
  crm_perf_setting = crm_au.account.crm_performance_setting
  json.kpi_scheme_visible Crm::PerformanceSetting.scheme_visible?(crm_perf_setting, crm_au)
  json.kpi_sheet_visible Crm::PerformanceSetting.sheet_visible?(crm_perf_setting, crm_au)
else
  json.kpi_scheme_visible false
  json.kpi_sheet_visible false
end
json.ui_settings resource.ui_settings
json.uid resource.uid
json.type resource.type
json.accounts do
  json.array! resource.account_users do |account_user|
    json.id account_user.account_id
    json.name account_user.account.name
    json.status account_user.account.status
    json.onboarding_step account_user.account.onboarding_step
    json.active_at account_user.active_at
    json.role account_user.role
    json.crm_role account_user.crm_role
    json.can_access_crm account_user.can_access_crm?
    json.permissions account_user.permissions
    # the actual availability user has configured
    json.availability account_user.availability
    # availability derived from presence
    json.availability_status account_user.availability_status
    json.auto_offline account_user.auto_offline
    json.partial! 'api/v1/models/account_user', account_user: account_user if ChatwootApp.enterprise?
  end
end
