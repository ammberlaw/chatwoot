json.partial! 'api/v1/models/crm_commission_sheet', formats: [:json], resource: @sheet
json.added @added if defined?(@added)
# 提成点配置（品类→点位%），前端逐行查表算提成基数/工资。
json.commission_rates Crm::CommissionRate.map_for(Current.account)
