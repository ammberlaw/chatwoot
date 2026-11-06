class Crm::PiPolicy < ApplicationPolicy
  def index?
    true
  end

  def summary?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def update?
    true
  end

  def prefill?
    true
  end

  # 新建/编辑时右侧实时预览要的抬头块，和 preview 同口径（只读、不含单据数据）。
  def preview_meta?
    true
  end

  def parse_pi?
    true
  end

  def xlsx?
    true
  end

  def preview?
    true
  end

  # 发出前体检：纯只读的对比（算术/缺字段/历史价），和 preview 同口径。
  def health_check?
    true
  end

  def destroy?
    true
  end
end
