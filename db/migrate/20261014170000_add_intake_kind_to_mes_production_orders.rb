# 接单方式：工程（魏工）和 PMC 的接单环节拆开。
# 用户原话：「我和魏工的流程能不能分开存在？新款他第一接单我第二接单；老款返单不需要他接单；
# 样机只能他接单，我不需要接单、也不会显示在我的工作台」。
class AddIntakeKindToMesProductionOrders < ActiveRecord::Migration[7.1]
  def change
    # 存量单按「新款」算：两段都要接单，与改造前行为一致。
    add_column :mes_production_orders, :intake_kind, :string, null: false, default: 'NEW'
  end
end
