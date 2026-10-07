# 期初库存导入：上传金蝶「库存查询表」→ 预检 → 导入。
# 预检只读不落库，把「几个仓、多少成品/原料、哪些编码没档案」摆给仓管看清楚再决定，
# 期初是账的地基，不能上传完直接就写进去。
class Api::V1::Accounts::Mes::StockOpeningsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization

  def preview
    render json: { payload: service.preview }
  rescue Mes::StockOpeningImportService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def create
    result = service.import!(
      create_missing_products: ActiveModel::Type::Boolean.new.cast(params[:create_missing_products]),
      new_product_line: params[:new_product_line].presence,
      replace: ActiveModel::Type::Boolean.new.cast(params[:replace])
    )
    render json: { payload: result }
  rescue Mes::StockOpeningImportService::Error, ActiveRecord::RecordInvalid, StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def service
    raise Mes::StockOpeningImportService::Error, '请选择要导入的 Excel 文件' if params[:file].blank?

    Mes::StockOpeningImportService.new(account: Current.account, user: current_user, path: params[:file].tempfile.path)
  end

  # 期初是建库存，与过账同一道门（仓管）。
  def check_authorization
    return if Current.account_user.mes_can?(:stock)

    render json: { error: '只有仓管可以导入期初库存' }, status: :forbidden
  end
end
