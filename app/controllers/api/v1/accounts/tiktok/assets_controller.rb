# TK 固定资产登记：按部门收口，读写口径与支出台账一致。只登记不折旧。
class Api::V1::Accounts::Tiktok::AssetsController < Api::V1::Accounts::Tiktok::BaseController
  before_action :ensure_ledger_access
  before_action :fetch_asset, only: %i[update destroy]

  def index
    scope = visible_assets.includes(:department, :holder, files_attachments: :blob)
    scope = scope.where(department_id: params[:department_id]) if params[:department_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    @assets = scope.ordered
    @editable_department_ids = tiktok_scope.editable_department_ids
  end

  def create
    ensure_editable_department!(asset_params[:department_id])
    return if performed?

    @asset = Current.account.tiktok_assets.new(asset_params.merge(creator_id: Current.user&.id))
    attach_files
    @asset.save!
    render :show
  end

  def update
    ensure_editable_department!(@asset.department_id)
    return if performed?

    @asset.update!(asset_params)
    attach_files
    purge_removed_files
    render :show
  end

  def destroy
    ensure_editable_department!(@asset.department_id)
    return if performed?

    @asset.destroy!
    head :ok
  end

  private

  def ensure_ledger_access
    return if tiktok_scope.can_view_profit?

    render json: { error: '仅部门负责人与财务可查看固定资产' }, status: :forbidden
  end

  def visible_assets
    ids = tiktok_scope.profit_visible_department_ids
    ids == :all ? Current.account.tiktok_assets : Current.account.tiktok_assets.where(department_id: ids)
  end

  def ensure_editable_department!(department_id)
    ids = tiktok_scope.editable_department_ids
    return if ids == :all
    return if ids.include?(department_id.to_i)

    render json: { error: '无权修改该部门的固定资产' }, status: :forbidden
  end

  def fetch_asset
    @asset = visible_assets.find(params[:id])
  end

  def attach_files
    Array(params[:files]).compact_blank.each { |file| @asset.files.attach(file) }
  end

  def purge_removed_files
    ids = Array(params[:remove_file_ids]).map(&:to_i).reject(&:zero?)
    return if ids.empty?

    @asset.files.where(id: ids).find_each(&:purge)
  end

  def asset_params
    params.require(:asset).permit(:department_id, :name, :code, :category, :purchased_on,
                                  :amount, :holder_id, :location, :status, :remark)
  end
end
