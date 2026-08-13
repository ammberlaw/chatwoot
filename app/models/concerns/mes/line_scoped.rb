# 产品线归属：create 时按优先级 stamp product_line —— 显式赋值 > 父级带出 > 控制器兜底（当前切换的产线）。
# 派生单据（生产订单/库存/出库/报工/质检/SN）由 product_line_source 从父级带；
# 主数据（物料/仓库/BOM/采购）由表单显式选，兜底用当前产线。
module Mes::LineScoped
  extend ActiveSupport::Concern

  included do
    before_validation :assign_product_line, on: :create
    scope :for_product_line, ->(line) { line.present? ? where(product_line: line) : all }
  end

  # 控制器把「当前切换的产线」塞进来作兜底。
  attr_writer :fallback_product_line

  private

  def assign_product_line
    return if product_line.present?

    self.product_line = product_line_source&.product_line || @fallback_product_line
  end

  # 各模型覆写：返回带 product_line 的父记录（无父则 nil，走兜底）。
  def product_line_source
    nil
  end
end
