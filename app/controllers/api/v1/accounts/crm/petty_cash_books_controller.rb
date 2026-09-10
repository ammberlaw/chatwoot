class Api::V1::Accounts::Crm::PettyCashBooksController < Api::V1::Accounts::Crm::BaseController
  # 财务身份常无 crm_role，会被 CRM 总门禁拦掉；与提成表同款跳过总门禁，
  # 可见范围与写权限在本控制器内按角色把关。
  skip_before_action :ensure_crm_access
  before_action :ensure_visible!
  before_action :ensure_writable!, only: [:create, :update, :destroy]
  before_action :fetch_book, only: [:update, :destroy]

  def index
    @books = visible_books.includes(:org_department, :entries).ordered
    @can_manage = can_write?
    @led_department_ids = led_department_ids
  end

  def create
    @book = Current.account.crm_petty_cash_books.new(book_params)
    @book.save!
    render :show
  end

  def update
    @book.update!(book_params)
    render :show
  end

  # 有流水的台账本不给删（结余和历史会一起消失），只能停用。
  def destroy
    return render json: { error: '该台账本已有流水，不能删除；可改为「停用」' }, status: :unprocessable_entity if @book.entries.exists?

    @book.destroy!
    head :ok
  end

  private

  def fetch_book
    @book = Current.account.crm_petty_cash_books.find(params[:id])
  end

  # 记账权：财务 / 管理员 / 副管理员。
  def can_write?
    au = Current.account_user
    au.present? && (au.crm_finance? || au.crm_deputy_admin?)
  end

  # 可见范围：有记账权的看全部；其余人只看自己带的部门那本（部门负责人）。
  def visible_books
    return Current.account.crm_petty_cash_books if can_write?

    Current.account.crm_petty_cash_books.where(org_department_id: led_department_ids)
  end

  def led_department_ids
    @led_department_ids ||= Current.account_user&.led_department_ids || []
  end

  def ensure_visible!
    return if can_write? || led_department_ids.any?

    render json: { error: '无权查看备用金台账' }, status: :forbidden
  end

  def ensure_writable!
    return if can_write?

    render json: { error: '仅财务与管理员可维护备用金台账' }, status: :forbidden
  end

  def book_params
    params.require(:book).permit(:name, :org_department_id, :opening_balance, :active, :remark)
  end
end
