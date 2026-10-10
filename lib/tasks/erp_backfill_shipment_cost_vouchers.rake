# 给**已出库**的销售出库单补「成本结转」凭证（借 主营业务成本 / 贷 库存商品）。
#
# 背景：Erp::AutoVoucherService#for_shipment_cost 原先只认挂在出库单名下的成本行，
# 那是现货轨道的成本来源；定制单的成本由 CostRollupService 挂在**生产订单**上，
# 于是定制单出库只出了收入凭证、没出成本凭证——利润表只有收入没有成本，毛利虚高。
# 取数口径已修好，但凭证只在出库动作时生成，**历史已出库的单不会自己补**，故有此任务。
#
# 幂等：凭证生成走 create_voucher!（按来源单据加锁 + 替换旧草稿），重复跑不会出两张。
# 已过账的那张不动——金额若有变化会抛错提示财务红冲，这里捕获后只记一行，不中断整批。
#
# 用法（先看一遍再真跑）：
#   bundle exec rails erp:backfill_shipment_cost_vouchers DRY_RUN=1
#   bundle exec rails erp:backfill_shipment_cost_vouchers
module ErpShipmentCostBackfill
  Stat = Struct.new(:created, :skipped, :failed) do
    def to_s = "生成 #{created}，无成本/已有 #{skipped}，异常 #{failed}"
  end

  def self.run(dry_run:)
    stat = Stat.new(0, 0, 0)
    Account.find_each { |account| run_account(account, dry_run, stat) }
    stat
  end

  def self.run_account(account, dry_run, stat)
    rule = account.erp_auto_voucher_rules.find_by(event_key: Erp::AutoVoucherRule::SHIPMENT_COST)
    return unless rule&.is_active

    service = Erp::AutoVoucherService.new(account)
    account.mes_shipments.where(status: 'SHIPPED').order(:id).find_each do |shipment|
      run_shipment(service, shipment, dry_run, stat)
    end
  end

  # 只补**缺失**的那张，已有的一概不动：财务可能已经在草稿上改过摘要/日期，
  # 补数任务不该把人家的改动覆盖掉；已过账的更不能动（要动得走红冲）。
  def self.run_shipment(service, shipment, dry_run, stat)
    return stat.skipped += 1 if cost_voucher_exists?(shipment)

    amount = service.shipment_cost_micros(shipment)
    return stat.skipped += 1 if amount <= 0

    label = "#{shipment.shipment_no} ¥#{(amount / 1_000_000.0).round(2)}"
    return dry_log(label, stat) if dry_run

    voucher = service.for_shipment_cost(shipment)
    voucher.present? ? log_created(label, voucher, stat) : stat.skipped += 1
  rescue StandardError => e
    stat.failed += 1
    puts "跳过 #{label || shipment.shipment_no}：#{e.message}"
  end

  def self.cost_voucher_exists?(shipment)
    shipment.account.erp_vouchers
            .where(source_type: "Mes::Shipment#{Erp::AutoVoucherService::COST_SOURCE_SUFFIX}",
                   source_id: shipment.id)
            .where.not(status: Erp::Voucher::VOID).exists?
  end

  def self.dry_log(label, stat)
    puts "[dry-run] 待补 #{label}"
    stat.created += 1
  end

  def self.log_created(label, voucher, stat)
    puts "已补 #{label} → #{voucher.voucher_no}"
    stat.created += 1
  end
end

namespace :erp do
  desc 'Backfill cost-transfer vouchers for already-shipped sales shipments (idempotent)'
  task backfill_shipment_cost_vouchers: :environment do
    dry_run = ENV['DRY_RUN'].present?
    stat = ErpShipmentCostBackfill.run(dry_run: dry_run)
    puts "#{dry_run ? '[dry-run] ' : ''}补凭证完成：#{stat}"
  end
end
