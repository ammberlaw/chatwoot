# 不变量守卫（纯静态扫描，不 boot Rails/无需 DB）：销售订单金额跨币种聚合必须折算 RMB。
#
# 背景：金额存 native 币种的 order_amount_micros；折算 RMB 的规范口径是
# Crm::SalesOrder::RMB_AMOUNT_MICROS_SQL（= ROUND(order_amount_micros * COALESCE(exchange_rate,1))）。
# 曾有「我的目标」「经营月报」直接 sum(:order_amount_micros)，导致外币订单按 1:1 计入 RMB，
# 达成率严重低算、月报冠军颁错人。此守卫防同类回归：任何 sum(:order_amount_micros) 都视为违规。
RSpec.describe 'Money currency-normalization guard' do
  repo_root = File.expand_path('../..', __dir__)

  it '没有任何代码直接 sum(:order_amount_micros)（必须用 RMB_AMOUNT_MICROS_SQL 折算）' do
    offenders = Dir.glob(File.join(repo_root, 'app', '**', '*.rb')).select do |file|
      File.read(file).include?('sum(:order_amount_micros)')
    end.map { |f| f.sub("#{repo_root}/", '') }

    expect(offenders).to be_empty,
                         "以下文件直接对 order_amount_micros 求和，未按币种折算 RMB：\n" \
                         "#{offenders.map { |f| "  - #{f}" }.join("\n")}\n" \
                         '改用 .sum(Arel.sql(Crm::SalesOrder::RMB_AMOUNT_MICROS_SQL))。'
  end
end
