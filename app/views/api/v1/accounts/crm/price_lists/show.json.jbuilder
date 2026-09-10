json.can_manage @can_manage
json.partial! 'api/v1/models/crm_price_list', formats: [:json], resource: @price_list, with_items: true
