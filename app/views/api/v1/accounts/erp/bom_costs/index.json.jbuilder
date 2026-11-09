json.payload do
  json.array! @bom_costs do |row|
    json.partial! 'api/v1/models/erp_bom_cost', formats: [:json], resource: row
    # 按 BOM 现算的单台材料成本（Erp::BomMaterialCostService）。只给参考值，不落库：
    # 材料成本栏手工填的那批是财务认过的数，不该被现查的采购价冲掉，所以前端只在
    # 存库值为 0 时拿它兜底显示，并标明是按 BOM 算的。做过 BOM 的产品才有这几项。
    bom = @bom_materials[row.crm_product_id]
    json.bom_no bom&.bom&.bom_no
    json.bom_material_cost_micros bom&.unit_micros
    json.bom_item_count bom&.item_count
    json.bom_unpriced_count bom&.unpriced_count
  end
end
json.meta do
  json.count @bom_costs_count
end
