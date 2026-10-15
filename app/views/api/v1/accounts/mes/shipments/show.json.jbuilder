# detail: true —— 多下发收款情况（财务审核的依据）。列表不给：逐行算回款进度是 N+1。
json.partial! 'api/v1/models/mes_shipment', formats: [:json], resource: @shipment, detail: true
