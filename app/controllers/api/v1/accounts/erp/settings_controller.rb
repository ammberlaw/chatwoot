# 账套级财务政策（erp_settings 一行）。
#
# 这几个字段原先只能改库——「税率设定可以自己改」等于没做到。财务改政策不该排开发。
class Api::V1::Accounts::Erp::SettingsController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization

  def show
    render json: { payload: payload, meta: meta }
  end

  def update
    setting = Erp::Setting.for_account(Current.account)
    setting.assign_attributes(setting_params)
    setting.save!
    @setting = setting
    render json: { payload: payload, meta: meta }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  private

  def check_authorization
    authorize(Erp::Setting)
  end

  def setting
    @setting ||= Erp::Setting.for_account(Current.account)
  end

  def payload
    {
      fiscal_start_date: setting.fiscal_start_date,
      default_output_tax_rate: setting.default_output_tax_rate,
      amount_includes_tax: setting.amount_includes_tax,
      receivables_enabled: setting.receivables_enabled
    }
  end

  # 改启用日的影响要当场看得见：日切前后各有多少张单会进/不进待建账。
  # 光给个日期框，财务没法判断填哪天是对的。
  def meta
    scope = Current.account.crm_sales_orders.where.not(status: %w[PENDING_CONFIRMATION CANCELLED])
    first_order = scope.minimum(:order_date)
    { total_orders: scope.count,
      earliest_order_date: first_order&.to_date,
      pending_after_cutoff: setting.fiscal_start_date ? scope.where(order_date: setting.fiscal_start_date.beginning_of_day..).count : scope.count }
  end

  def setting_params
    params.require(:setting).permit(:fiscal_start_date, :default_output_tax_rate, :amount_includes_tax,
                                    :receivables_enabled)
  end
end
