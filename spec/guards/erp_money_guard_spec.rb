# frozen_string_literal: true

require 'rails_helper'

# ERP 金额不变量守卫。与 spec/guards/money_currency_guard_spec.rb 同思路，
# 只是 ERP 这边多币种的表更多、且**没有**预折算列（除了 erp_voucher_lines.base_amount_micros）。
#
# 背景：ERP 的应收/应付/收款/付款四张表都存**原币** amount，币种在 currency 列、汇率在 exchange_rate。
# 跨币种求和必须过各模型的 BASE_*_MICROS_SQL 折成本位币；直接 sum 原币列
# ＝把 1000 美元当 1000 人民币加进去。看板 KPI、台账合计、供应商对账都踩过。
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ERP 金额口径守卫' do
  # rubocop:enable RSpec/DescribeClass
  repo_root = File.expand_path('../..', __dir__)

  # 表 → 该表里存原币、跨币种求和必须先折算的列
  native_money_columns = {
    'Erp::Receivable' => %w[total_amount_micros received_amount_micros],
    'Erp::Payable' => %w[total_amount_micros paid_amount_micros],
    'Erp::ReceiptRecord' => %w[amount_micros],
    'Erp::PaymentRecord' => %w[amount_micros]
  }.freeze

  # 这些地方**就该**用原币，不算违规：
  # - 核销：金额按原币记进同币种台账（AllocationService 已强制两边币种一致）
  # - 单据自身的已核销额：与自己的 amount_micros 同币种比
  # - 资金账户余额：一个账户只有一种币，余额本来就是原币
  # - 调汇：期末应有本位币 = **原币余额** × 期末汇率，取原币是算法要求
  # - 两账对平：已按 currency: 'CNY' 收口后再 sum
  allowed = [
    'app/services/erp/allocation_service.rb',
    'app/services/erp/revaluation_service.rb',
    'app/services/erp/reconciliation_service.rb',
    'app/services/erp/period_checklist.rb',
    'app/models/erp/receipt_record.rb',
    'app/models/erp/payment_record.rb',
    'app/models/erp/cash_account.rb'
  ].freeze

  erp_sources = lambda do |root|
    Dir.glob(File.join(root, 'app', '{models,services,controllers}', '**', '*.rb'))
       .select { |f| f.include?('/erp/') }
  end

  it '跨币种求和都折了本位币（没有裸 sum 原币金额列）' do
    offenders = []
    erp_sources.call(repo_root).each do |file|
      rel = file.sub("#{repo_root}/", '')
      next if allowed.include?(rel)

      body = File.read(file)
      native_money_columns.values.flatten.uniq.each do |col|
        body.each_line.with_index(1) do |line, no|
          next unless line.include?("sum(:#{col})") || line.match?(/SUM\(\s*#{col}\s*\)/)

          offenders << "#{rel}:#{no}  #{line.strip}"
        end
      end
    end

    expect(offenders).to be_empty,
                         "以下位置直接对原币金额求和，未折本位币：\n#{offenders.map { |o| "  - #{o}" }.join("\n")}\n" \
                         '改用对应模型的 BASE_*_MICROS_SQL（如 Erp::Receivable::BASE_TOTAL_MICROS_SQL）。'
  end

  it '四张多币种表都定义了折本位币的 SQL 常量' do
    missing = native_money_columns.keys.reject do |model|
      model.constantize.constants.any? { |c| c.to_s.start_with?('BASE_') && c.to_s.end_with?('_MICROS_SQL') }
    end

    expect(missing).to be_empty, "这些模型缺 BASE_*_MICROS_SQL 常量：#{missing.join(', ')}"
  end

  it '折算 SQL 都带 COALESCE（汇率为空时按 1 折，不能让整行变 NULL 被 SUM 跳过）' do
    bad = native_money_columns.keys.flat_map do |model|
      klass = model.constantize
      klass.constants.grep(/\ABASE_.*_MICROS_SQL\z/).filter_map do |const|
        sql = klass.const_get(const)
        "#{model}::#{const}" unless sql.include?('COALESCE')
      end
    end

    expect(bad).to be_empty, "这些折算 SQL 少了 COALESCE：#{bad.join(', ')}"
  end
end
