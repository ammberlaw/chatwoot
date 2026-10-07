# 会计启用日（账套切过来的那一天）。
#
# 为什么必须有：待建账口径原本是「已确认 且 没建过账」，于是把从小满迁进来的
# 484 张历史单（2227 万，其中 392 张是迁移当天就 COMPLETED 的）全列进去——
# 那些钱系统上线前早收完了，建出来就是一堆假应收。日切之前的余额走期初建账
# 一笔总额进总账，日切之后的单才逐张建台账。
#
# 允许为空＝沿用现状（不切，全列），不想在迁移里替财务拍日期。
class AddFiscalStartDateToErpSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :erp_settings, :fiscal_start_date, :date
  end
end
