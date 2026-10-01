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

  def company_headers?
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

  def destroy?
    true
  end
end
