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
  def transactions
    scope = Current.account.erp_cash_transactions.includes(:cash_account, :created_by)
    scope = scope.where(cash_account_id: params[:cash_account_id]) if params[:cash_account_id].present?
    scope = scope.where(happened_at: params[:from]..) if params[:from].present?
    scope = scope.where(happened_at: ..params[:to]) if params[:to].present?
    @transactions = scope.order(happened_at: :desc, id: :desc).limit(200)
    render 'api/v1/accounts/erp/cash_accounts/transactions'
  end

  # 内部划转：转出一笔 + 转入一笔 + 自动凭证。
  def transfer
    Erp::CashLedgerService.new(Current.account, current_user).transfer!(
      from_id: params[:from_id], to_id: params[:to_id],
      amount_micros: params[:amount_micros].to_i,
      happened_at: params[:happened_at].presence || Time.zone.today,
      summary: params[:summary]
    )
    @cash_accounts = cash_accounts_scope
    render 'api/v1/accounts/erp/cash_accounts/index'
  rescue Erp::CashLedgerService::Error, Erp::AutoVoucherService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

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
      :opening_balance_micros, :is_active, :position, :remark
    )
  end
end
