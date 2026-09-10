# TK 支出台账：按部门收口（店铺选填）。读写口径与利润表一致——
# 管理层/财务可读全部（财务只读），部门负责人限本部门。
class Api::V1::Accounts::Tiktok::ExpensesController < Api::V1::Accounts::Tiktok::BaseController
  before_action :ensure_ledger_access
  before_action :fetch_expense, only: %i[update destroy]

  def index
    scope = visible_expenses.includes(:department, :shop, :creator, files_attachments: :blob)
    scope = scope.where(department_id: params[:department_id]) if params[:department_id].present?
    scope = scope.where(shop_id: params[:shop_id]) if params[:shop_id].present?
    scope = scope.in_month(params[:month]) if params[:month].present?
    @expenses = scope.ordered
    @editable_department_ids = tiktok_scope.editable_department_ids
  end

  def create
    ensure_editable_department!(expense_params[:department_id])
    return if performed?

    @expense = Current.account.tiktok_expenses.new(expense_params.merge(creator_id: Current.user&.id))
    attach_files
    @expense.save!
    render :show
  end

  def update
    ensure_editable_department!(@expense.department_id)
    return if performed?

    @expense.update!(expense_params)
    attach_files
    purge_removed_files
    render :show
  end

  def destroy
    ensure_editable_department!(@expense.department_id)
    return if performed?

    @expense.destroy!
    head :ok
  end

  private

  # 含金额的经营数据，与利润表同门槛：普通部门成员不可见。
  def ensure_ledger_access
    return if tiktok_scope.can_view_profit?

    render json: { error: '仅部门负责人与财务可查看支出台账' }, status: :forbidden
  end

  def visible_expenses
    ids = tiktok_scope.profit_visible_department_ids
    ids == :all ? Current.account.tiktok_expenses : Current.account.tiktok_expenses.where(department_id: ids)
  end

  def ensure_editable_department!(department_id)
    ids = tiktok_scope.editable_department_ids
    return if ids == :all
    return if ids.include?(department_id.to_i)

    render json: { error: '无权修改该部门的支出台账' }, status: :forbidden
  end

  def fetch_expense
    @expense = visible_expenses.find(params[:id])
  end

  def attach_files
    Array(params[:files]).compact_blank.each { |file| @expense.files.attach(file) }
  end

  def purge_removed_files
    ids = Array(params[:remove_file_ids]).map(&:to_i).reject(&:zero?)
    return if ids.empty?

    @expense.files.where(id: ids).find_each(&:purge)
  end

  def expense_params
    params.require(:expense).permit(:department_id, :shop_id, :expense_date, :category, :subject,
                                    :amount, :currency, :remark)
  end
end
