class Api::V1::Accounts::Crm::PettyCashEntriesController < Api::V1::Accounts::Crm::BaseController
  skip_before_action :ensure_crm_access
  before_action :fetch_book
  before_action :ensure_writable!, only: [:create, :update, :destroy]
  before_action :fetch_entry, only: [:update, :destroy]

  # 一本账的流水，按日期正序（与 Excel 一致，逐行结余在前端按顺序累加）。
  # month 传 YYYY-MM 只看该月；不传看全部。
  def index
    scope = @book.entries.includes(:handler, :created_by, files_attachments: :blob)
    scope = scope.in_month(params[:month]) if params[:month].present?
    @entries = scope.ordered
    # 期初：本月之前的净额并入期初，月度视图的结余才接得上。
    @opening = @book.opening_balance.to_d + prior_net
  end

  def create
    @entry = @book.entries.new(entry_params.merge(account_id: Current.account.id, created_by_id: current_user.id))
    attach_files
    @entry.save!
    render :show
  end

  def update
    @entry.update!(entry_params)
    attach_files
    purge_removed_files
    render :show
  end

  def destroy
    @entry.destroy!
    head :ok
  end

  private

  def fetch_book
    @book = Current.account.crm_petty_cash_books.find(params[:petty_cash_book_id])
    return if can_write? || led_department_ids.include?(@book.org_department_id)

    render json: { error: '无权查看该备用金台账' }, status: :forbidden
  end

  def fetch_entry
    @entry = @book.entries.find(params[:id])
  end

  # 本月之前的净额（存入 − 支出）。不按月筛选时为 0。
  def prior_net
    return 0.to_d if params[:month].blank?

    date = Date.parse("#{params[:month]}-01")
    prior = @book.entries.where(entry_date: ...date)
    prior.where(direction: 'IN').sum(:amount) - prior.where(direction: 'OUT').sum(:amount)
  end

  # 财务/管理员/副管理员：全部账本可记。
  def can_write?
    au = Current.account_user
    au.present? && (au.crm_finance? || au.crm_deputy_admin?)
  end

  # 部门负责人：只能记自己带的部门那本账（本账本的流水）。
  def can_record_book?
    can_write? || led_department_ids.include?(@book.org_department_id)
  end

  def led_department_ids
    @led_department_ids ||= Current.account_user&.led_department_ids || []
  end

  def ensure_writable!
    return if can_record_book?

    render json: { error: '只能记本部门的备用金台账' }, status: :forbidden
  end

  def attach_files
    Array(params[:files]).compact_blank.each { |file| @entry.files.attach(file) }
  end

  def purge_removed_files
    ids = Array(params[:remove_file_ids]).map(&:to_i).reject(&:zero?)
    return if ids.empty?

    @entry.files.where(id: ids).find_each(&:purge)
  end

  def entry_params
    params.require(:entry).permit(:entry_date, :direction, :amount, :subject, :channel, :category,
                                  :handler_id, :remark)
  end
end
