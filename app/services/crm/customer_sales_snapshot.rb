# 这家客户「上次买了什么、现在欠什么、货到哪了、多久没联系」——摆在邮件页上，
# 业务员读信的时候一眼就有，不用先去问 AI、也不用切到客户详情页再切回来。
#
# 为什么做成推过去而不是等人来查：AI 助手手里早就有这些工具（历史报价、订单进度、
# 往来摘要），对 41 个人开放，可是每月只被问 214 次、人均 5 次。不是工具不好，
# 是它只会等人问，而人忙起来根本想不起来。所以改成送到他已经在看的那一屏上。
#
# ⚠️ 只给**销售自己那一侧**的事实：买了什么、什么价、钱付没付、货到哪一步。
# 成本、供应商、毛利一个字都不出现（公司硬规矩）；生产进度只露阶段名，
# 不摆车间里的工序细节。
class Crm::CustomerSalesSnapshot
  # 上次成交最多摆几行明细。摆全了是一张表，不是「一眼就有」。
  MAX_ITEMS = 3
  # 在跟的 PI / 在产订单各最多摆几条。
  MAX_DOCS = 3

  # 还没收到钱的 PI。VOID 作废的不算，PAID 的已经转成订单了。
  OPEN_PI_STATUSES = %w[DRAFT UNPAID].freeze
  # 「货还没到客户手上」的订单阶段。
  IN_PROGRESS_STATUSES = %w[PENDING_CONFIRMATION IN_PRODUCTION PENDING_SHIPMENT].freeze
  # 已经交付完的——「上次成交」只认这些。在产/待出货的归下面「在途」那一行，
  # 否则同一张单会同时出现在两处（实测在产单会把真正的上一单顶掉）。
  DELIVERED_STATUSES = %w[SHIPPED COMPLETED].freeze
  PI_STATUS_LABELS = { 'DRAFT' => '草稿', 'UNPAID' => '待付款' }.freeze

  def initialize(account:, customer:)
    @account = account
    @customer = customer
  end

  def call
    {
      last_order: last_order_payload,
      open_pis: open_pis_payload,
      in_progress: in_progress_payload,
      last_touch_days: last_touch_days
    }
  end

  private

  def orders = @account.crm_sales_orders.where(crm_customer_id: @customer.id)

  # 上次成交：最近一张**已经交付完**的订单。带前几行明细——「上次买了什么、什么价」
  # 才是谈这一单时真正要对的东西，只给个总额用处不大。
  def last_order_payload
    order = orders.where(status: DELIVERED_STATUSES).order(order_date: :desc, id: :desc).first
    return nil if order.nil?

    {
      order_no: order.order_no,
      order_date: order.order_date&.to_date,
      amount: money(order.order_amount_micros),
      currency: order.order_currency,
      status_label: Crm::SalesOrder::STATUS_LABELS[order.status],
      items: order.line_item_rows.first(MAX_ITEMS).map { |row| item_row(row) },
      more_items: [order.line_item_rows.size - MAX_ITEMS, 0].max
    }
  end

  def item_row(row)
    { name: row[:name].presence || row[:sku], spec: row[:spec],
      quantity: row[:quantity], unit_price: row[:unit_price] }
  end

  # 在跟的 PI：开了单还没收到钱的。业务员回信时最常要确认的就是这个。
  def open_pis_payload
    @account.crm_pis.where(crm_customer_id: @customer.id, status: OPEN_PI_STATUSES)
            .order(pi_date: :desc, id: :desc).limit(MAX_DOCS)
            .map do |pi|
      { pi_no: pi.pi_no, pi_date: pi.pi_date&.to_date,
        amount: money(pi.total_amount_micros), currency: pi.currency,
        status_label: PI_STATUS_LABELS[pi.status] }
    end
  end

  # 在途订单：只给单号和阶段名。客户问「我的货到哪了」时照着念就行。
  def in_progress_payload
    orders.where(status: IN_PROGRESS_STATUSES).order(order_date: :desc, id: :desc).limit(MAX_DOCS)
          .map do |order|
            { order_no: order.order_no, status_label: Crm::SalesOrder::STATUS_LABELS[order.status],
              expected_date: order.delivery_date&.to_date }
          end
  end

  # 多久没联系：收发都算（我们发出去的也是接触）。一封都没有就返回 nil，
  # 前端显示「还没有往来」，不要显示成 0 天。
  def last_touch_days
    last = @account.crm_emails.where(crm_customer_id: @customer.id).maximum(:email_date)
    last && ((Time.current - last) / 86_400).floor
  end

  def money(micros)
    return nil if micros.blank?

    (micros.to_i / 1_000_000.0).round(2)
  end
end
