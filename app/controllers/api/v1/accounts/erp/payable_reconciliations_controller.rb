# 应付「先对账再建账」：收了货先在这里跟供应商核对，对好了才落应付台账。
#
# 2026-10-21 之前是收货即建账（入库单一过账就把欠款写进台账）。财务定的流程是反过来的——
# 先对账、对好了再建账，否则还没核对的数字先摆进了欠款里，付款和账龄都跟着错。
# 单独成一个控制器：它是建账**之前**的一道流程，与应付台账的增删改查不是一回事。
class Api::V1::Accounts::Erp::PayableReconciliationsController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization

  # 待对账清单：每行＝一张采购单 × 一家供应商，按**已过账**的实收数量算该欠多少，
  # 与台账上已建的金额对比。两者一分不差就不在清单里（已经对过账了）。
  def index
    @rows = Erp::LedgerBuilderService.new(Current.account).pending_reconciliation
    render json: { payload: @rows, count: @rows.size }
  end

  # 对好了，建账。
  def confirm
    order = Current.account.mes_purchase_orders.find(params[:mes_purchase_order_id])
    builder = Erp::LedgerBuilderService.new(Current.account)
    payable = builder.confirm_reconciliation!(purchase_order: order, supplier_id: params[:mes_supplier_id].to_i)
    render json: { payload: { payable_no: payable.payable_no, warning: builder.payable_warning } }
  rescue Erp::LedgerBuilderService::Error, ActiveRecord::RecordInvalid => e
    render json: { error: e.message.delete_prefix('Validation failed: ') }, status: :unprocessable_entity
  end

  private

  def check_authorization
    authorize(Erp::Payable)
  end
end
