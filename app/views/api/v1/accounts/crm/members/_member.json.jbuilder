json.id member.id
json.user_id member.user_id
json.name member.user.name
json.crm_name member.user.crm_name
json.email member.user.email
json.avatar_url member.user.avatar_url
json.role member.role
json.is_admin member.administrator?
json.crm_role member.crm_role
json.crm_finance member.crm_finance
json.in_sales_rank member.in_sales_rank
json.mes_roles member.effective_mes_roles
json.erp_role member.erp_role if member.has_attribute?(:erp_role)
json.can_access_crm member.can_access_crm?
json.module_access member.module_access
json.deactivated_at member.deactivated_at
# 部门名（选人弹窗分组用）；主部门在前。控制器已预取，这里不查库。
json.departments(defined?(@departments_by_user) ? (@departments_by_user[member.user_id] || []) : [])
