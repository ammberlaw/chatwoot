# 提成表：人人可访问（数据范围与操作权在控制器按角色/审批链控制）。
class Crm::CommissionSheetPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def create? = true
  def update? = true
  def destroy? = true
  def pull_orders? = true
  def submit? = true
  def approve? = true
  def return_sheet? = true
  def xlsx? = true
  def mark_paid? = true
  def unmark_paid? = true
  def rates? = true
  def save_rates? = true
  def selectable_orders? = true
  def import_orders? = true
end
