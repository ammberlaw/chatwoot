json.partial! 'api/v1/models/crm_kpi_sheet', formats: [:json], resource: @sheet

# 审批人(人事/总经理)id 随考核表下发，供前端判断按钮显示——
# 避免前端去拉「绩效设置」接口(那接口仅管理员/副管可访问，人事/总经理拉不到→按钮不显示)。
setting = Crm::PerformanceSetting.for_account(@sheet.account)
json.hr_owner_id setting&.hr_owner_id
json.gm_owner_id setting&.gm_owner_id
