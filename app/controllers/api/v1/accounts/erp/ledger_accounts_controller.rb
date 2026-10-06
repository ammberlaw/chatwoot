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

  # 存货科目映射：产品档案的「来源类别」→ 存货科目。
  # 类别清单实时从产品档案聚合（含各类产品数），不另存一张字典表——
  # 仓库那边随时会加新类别，存字典就得两头同步。未配置的类别前端显示默认值。
  def inventory_map
    setting = Erp::Setting.for_account(Current.account)
    saved = setting.inventory_account_map
    rows = Current.account.crm_products
                  .where.not(source_category: [nil, ''])
                  .group(:source_category).count
                  .sort_by { |category, count| [-count, category] }
                  .map do |category, count|
      { category: category, product_count: count,
        code: saved[category] || Erp::Setting::RAW_MATERIAL_CODE,
        suggested: Erp::Setting.suggest_inventory_code(category),
        configured: saved.key?(category) }
    end
    render json: {
      payload: rows,
      meta: { default_code: Erp::Setting::RAW_MATERIAL_CODE,
              options: inventory_option_list,
              configured_count: saved.keys.size }
    }
  end

  # 整表提交（类别几百个、一次改一批，逐条 PATCH 不如整体覆盖来得稳）。
  # 只收合法科目编码，落默认的键不存——省得映射表被一堆「等于默认」的噪声撑大。
  def update_inventory_map
    setting = Erp::Setting.for_account(Current.account)
    # 不能用 require(:map)：全部清空时客户端送的是空 {}，Rails 的 deep_munge 会把空哈希
    # 直接剔掉，require 当成缺参数抛 422——结果「配过的类别一条都删不掉」。
    raw = params[:map]
    incoming = raw.respond_to?(:permit!) ? raw.permit!.to_h : (raw || {}).to_h
    cleaned = incoming.filter_map do |category, code|
      next if category.to_s.strip.blank?
      next unless Erp::Setting::INVENTORY_ACCOUNT_CODES.include?(code.to_s)
      next if code.to_s == Erp::Setting::RAW_MATERIAL_CODE

      [category.to_s, code.to_s]
    end.to_h
    setting.inventory_account_map = cleaned
    setting.save!
    render json: { payload: { configured_count: cleaned.size } }
  end

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

  # 下拉选项：三个存货科目，名字取账套里真实的科目名（财务可能改过名）。
  def inventory_option_list
    names = Current.account.erp_ledger_accounts
                   .where(code: Erp::Setting::INVENTORY_ACCOUNT_CODES).pluck(:code, :name).to_h
    fallback = { Erp::Setting::RAW_MATERIAL_CODE => '原材料',
                 Erp::Setting::FINISHED_GOODS_CODE => '库存商品',
                 Erp::Setting::SUBCONTRACT_CODE => '委托加工物资' }
    Erp::Setting::INVENTORY_ACCOUNT_CODES.map do |code|
      { code: code, name: names[code].presence || fallback[code] }
    end
  end

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
