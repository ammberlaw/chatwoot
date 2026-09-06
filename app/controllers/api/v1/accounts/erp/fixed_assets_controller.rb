# 固定资产：档案 CRUD + 月度折旧计提 + 处置报废。
class Api::V1::Accounts::Erp::FixedAssetsController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_asset, only: [:show, :update, :destroy, :dispose]

  def index
    scope = Current.account.erp_fixed_assets.includes(:department, :keeper)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where('asset_no ILIKE :t OR name ILIKE :t', t: "%#{params[:q].strip}%") if params[:q].present?
    @assets = scope.order(purchased_at: :desc, id: :desc)
    @summary = {
      original_micros: @assets.sum(&:original_value_micros),
      accumulated_micros: @assets.sum(&:accumulated_depreciation_micros)
    }
  end

  def show; end

  def create
    @asset = Current.account.erp_fixed_assets.create!(asset_params)
    render 'api/v1/accounts/erp/fixed_assets/show'
  end

  def update
    @asset.update!(asset_params)
    render 'api/v1/accounts/erp/fixed_assets/show'
  end

  def destroy
    return render json: { error: '已计提折旧的资产不能删除，可做处置或报废' }, status: :unprocessable_entity if @asset.depreciation_entries.exists?

    @asset.destroy!
    head :ok
  end

  # 一键计提本期折旧（汇总成一张待过账凭证）。
  def depreciate
    result = Erp::DepreciationService.new(Current.account, current_user).run!(params[:period])
    render json: result
  rescue Erp::DepreciationService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def dispose
    Erp::DepreciationService.new(Current.account, current_user).dispose!(
      @asset, disposed_at: params[:disposed_at].presence || Time.zone.today,
              income_micros: params[:income_micros].to_i, scrapped: params[:scrapped].to_s == 'true'
    )
    render 'api/v1/accounts/erp/fixed_assets/show'
  rescue Erp::DepreciationService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def fetch_asset
    @asset = Current.account.erp_fixed_assets.find(params[:id])
  end

  def check_authorization
    authorize(Erp::FixedAsset)
  end

  def asset_params
    params.require(:fixed_asset).permit(
      :name, :category, :purchased_at, :original_value_micros, :residual_rate, :useful_months,
      :department_id, :keeper_id, :remark
    )
  end
end
