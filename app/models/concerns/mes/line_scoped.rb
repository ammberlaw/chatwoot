# 产品线归属：create 时按优先级 stamp product_line —— 显式赋值 > 父级带出 > 控制器兜底（当前切换的产线）。
# 派生单据（生产订单/库存/出库/报工/质检/SN）由 product_line_source 从父级带；
# 主数据（物料/仓库/BOM/采购）由表单显式选，兜底用当前产线。
module Mes::LineScoped
  extend ActiveSupport::Concern

  included do
    before_validation :assign_product_line, on: :create
    scope :for_product_line, ->(line) { line.present? ? where(product_line: line) : all }
  end

  class_methods do
    # 主数据（BOM/物料/采购…）必须落在某条产线上。
    #
    # 兜底值来自「当前切换的产线」，而在「全部」视图下这个值是空的——建出来的单子
    # 之后切到任何一条产线都看不见，只有「全部」能翻到，等于凭空消失。生产上已经这么
    # 丢过 3 条 BOM（9/1、9/3、9/11，全是商显的单），不是偶发。
    #
    # 派生单据（生产订单/库存/报工…）从父级继承，父级有值就不会空，故不默认开启；
    # 需要收口的模型自行调用本方法。
    # 只在 create 上校验：漏是从建单漏的，而存量的空产线记录（历史遗留）还要能编辑、
    # 能被脚本回填，保存时一律必填会把它们锁死。
    def require_product_line!
      validates :product_line,
                presence: { message: '不能为空——请在表单里选择产品线（或先在左上角切到具体产线）' },
                on: :create
    end
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
