# 会计科目表：全量返回（科目量级几十到几百，不分页），前端按 parent_id 组树。
# 初始化走 Erp::ChartOfAccountsService（国标模板，幂等补齐）。
class Api::V1::Accounts::Erp::LedgerAccountsController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_ledger_account, only: [:show, :update, :destroy]

  def index
    scope = Current.account.erp_ledger_accounts
    scope = scope.active if params[:active] == 'true'
    if params[:q].present?
      term = "%#{params[:q].strip}%"
      # 搜索命中的科目连同其祖先一起返回，否则前端组树会掉链子（明细挂不上分类）。
      matched = scope.where('code ILIKE :t OR name ILIKE :t', t: term).to_a
      ids = matched.flat_map { |a| a.ancestry_chain.map(&:id) }.uniq
      scope = Current.account.erp_ledger_accounts.where(id: ids)
    end
    @ledger_accounts = scope.order(:code)
  end

  def show; end

  def create
    @ledger_account = Current.account.erp_ledger_accounts.new(ledger_account_params)
    # 类别/方向/报表段跟随上级，避免手工建科目时挑错大类导致报表串类。
    inherit_from_parent(@ledger_account)
    @ledger_account.save!
    render 'api/v1/accounts/erp/ledger_accounts/show'
  end

  def update
    @ledger_account.assign_attributes(ledger_account_params)
    inherit_from_parent(@ledger_account)
    @ledger_account.save!
    render 'api/v1/accounts/erp/ledger_accounts/show'
  end

  def destroy
    @ledger_account.destroy!
    head :ok
  rescue ActiveRecord::RecordNotDestroyed
    render json: { error: @ledger_account.errors.full_messages.join('；') }, status: :unprocessable_entity
  end

  # 一键初始化/补齐国标标准科目表（幂等，不覆盖已有科目）。
  def initialize_standard
    result = Erp::ChartOfAccountsService.ensure_standard!(Current.account)
    render json: result
  end

  private

  def fetch_ledger_account
    @ledger_account = Current.account.erp_ledger_accounts.find(params[:id])
  end

  def check_authorization
    authorize(Erp::LedgerAccount)
  end

  def inherit_from_parent(record)
    parent = Current.account.erp_ledger_accounts.find_by(id: record.parent_id)
    return if parent.blank?

    record.category = parent.category
    record.direction ||= parent.direction
    record.bs_section = parent.bs_section if record.bs_section.blank?
  end

  def ledger_account_params
    params.require(:ledger_account).permit(
      :code, :name, :category, :direction, :parent_id, :is_group, :account_type,
      :currency, :bs_section, :is_active, :position, :remark, dimensions: []
    )
  end
end
