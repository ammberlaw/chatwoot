class Crm::KnowledgeDocPolicy < ApplicationPolicy
  def index?
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

  def attach?
    true
  end

  def detach?
    true
  end

  def audits?
    true
  end

  # 删除按文档级权限控制（个人文档归属人可删自己的），
  # 由控制器 ensure_doc_manageable 强制；此处放行到控制器层判断。
  def destroy?
    true
  end

  # 回收站仅管理员，由控制器 ensure_admin 强制。
  def recycle_bin?
    true
  end

  def restore?
    true
  end

  def purge?
    true
  end

  def purge_all?
    true
  end
end

Crm::KnowledgeDocPolicy.prepend_mod_with('Crm::KnowledgeDocPolicy')
