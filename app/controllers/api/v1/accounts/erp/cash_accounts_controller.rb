# 资金账户与出纳日记账：账户 CRUD + 流水查询 + 内部划转。
class Api::V1::Accounts::Erp::CashAccountsController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_cash_account, only: [:show, :update, :destroy]

  def index
    @cash_accounts = cash_accounts_scope
  end

  def show; end

  def create
    @cash_account = Current.account.erp_cash_accounts.create!(cash_account_params)
    render 'api/v1/accounts/erp/cash_accounts/show'
  end

  def update
    @cash_account.update!(cash_account_params)
    render 'api/v1/accounts/erp/cash_accounts/show'
  end

  def destroy
    return render json: { error: '该账户已有资金流水，不能删除，可停用' }, status: :unprocessable_entity if @cash_account.transactions.exists?

    @cash_account.destroy!
    head :ok
  end

  # 出纳日记账：某账户（或全部）的流水，按日期倒序。
  TRANSACTIONS_LIMIT = 200
  # 导出要的是整段流水，不是屏幕上那 200 笔；仍留上限免得一次拉爆内存（超了照样打 truncated）。
  EXPORT_TRANSACTIONS_LIMIT = 5_000

  def transactions
    scope = transactions_scope
    limit = transactions_limit
    # 日记账是要跟银行对账单核的表：截断必须显式打标，静默少一段流水=对不上还找不到原因。
    @transactions_count = scope.count
    @truncated = @transactions_count > limit
    @transactions = scope.order(happened_at: :desc, id: :desc).limit(limit)
    render 'api/v1/accounts/erp/cash_accounts/transactions'
  end

  # 资金报表：一个期间里每个账户的期初/收/支/期末 + 折 CNY 合计（ERP_SPEC §9.3）。
  def report
    render json: { payload: Erp::CashReportService.new(Current.account).call(period: params[:period].to_s) }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 内部划转：转出一笔 + 转入一笔 + 自动凭证。
  def transfer
    Erp::CashLedgerService.new(Current.account, current_user).transfer!(
      from_id: params[:from_id], to_id: params[:to_id],
      amount_micros: params[:amount_micros].to_i,
      happened_at: params[:happened_at].presence || Time.zone.today,
      summary: params[:summary],
      exchange_rate: params[:exchange_rate]
    )
    @cash_accounts = cash_accounts_scope
    render 'api/v1/accounts/erp/cash_accounts/index'
  rescue Erp::CashLedgerService::Error, Erp::AutoVoucherService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # 默认 200 笔够看；带 limit 的（导出）放宽到 5000 封顶。
  def transactions_limit
    requested = params[:limit].to_i
    return TRANSACTIONS_LIMIT unless requested.positive?

    [requested, EXPORT_TRANSACTIONS_LIMIT].min
  end

  def transactions_scope
    scope = Current.account.erp_cash_transactions.includes(:cash_account, :created_by)
    scope = scope.where(cash_account_id: params[:cash_account_id]) if params[:cash_account_id].present?
    scope = scope.where(happened_at: params[:from]..) if params[:from].present?
    scope = scope.where(happened_at: ..params[:to]) if params[:to].present?
    scope
  end

  # 票面要显示映射科目名，列表统一预加载（dev 的 Bullet 会对 N+1 直接抛 500）。
  def cash_accounts_scope
    Current.account.erp_cash_accounts.includes(:ledger_account).order(:position, :id)
  end

  def fetch_cash_account
    @cash_account = Current.account.erp_cash_accounts.find(params[:id])
  end

  def check_authorization
    authorize(Erp::CashAccount)
  end

  def cash_account_params
    params.require(:cash_account).permit(
      :name, :kind, :currency, :account_no, :bank_name, :ledger_account_id,
      :opening_balance_micros, :opening_base_amount_micros, :is_active, :position, :remark
    )
  end
end
