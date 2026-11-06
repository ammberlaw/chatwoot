class Crm::QuotePolicy < ApplicationPolicy
  def index?
    true
  end

  def summary?
    true
  end

  def show?
    true
  end

  def prefill?
    true
  end

  def xlsx?
    true
  end

  def preview?
    true
  end

  # 新建/编辑时右侧实时预览要的模板文案，和 preview 同口径（只读、不含单据数据）。
  def preview_meta?
    true
  end

  # 发出前体检：纯只读的对比（算术/缺字段/历史价），和 preview 同口径。
  def health_check?
    true
  end

  def convert_to_sales_order?
    true
  end

  def create?
    true
  end

  def update?
    true
  end

  # 删除报价单：与销售订单/PI/商机同口径放开（控制器已按可见范围 scope_docs_visible 限定）。
  # 原先仅 administrator 导致业务员删自己的报价也 401。
  def destroy?
    true
  end
end

Crm::QuotePolicy.prepend_mod_with('Crm::QuotePolicy')
