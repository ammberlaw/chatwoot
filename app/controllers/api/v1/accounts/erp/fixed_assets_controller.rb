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

  # Excel 批量导入：账套启用时把现有资产连「已提折旧」一次性搬进来。
  # 一条一条录几十上百台设备是开账最耗人的一段，期初资产空着折旧和净值就全是错的。
  # 逐行独立：错误行连行号报回去，对的照常建。
  def import
    return render json: { error: '请选择要导入的 Excel 文件' }, status: :unprocessable_entity if params[:file].blank?

    result = Erp::FixedAssetImportService.new(account: Current.account, path: params[:file].tempfile.path).import!
    render json: { payload: result }
  rescue Erp::FixedAssetImportService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def import_template
    send_data Erp::FixedAssetImportService.template_stream.read,
              filename: '固定资产导入模板.xlsx',
              type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
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
