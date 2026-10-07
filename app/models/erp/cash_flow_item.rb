# 现金流量项目（《企业会计准则第31号——现金流量表》标准项目）。
#
# 不建表：项目表由准则固定，不给用户增删改，硬编码成常量（系统精简原则）。
# 分录行上存的是这里的 code 字符串（`erp_voucher_lines.cash_flow_item`）。
#
# **与金蝶的差别**：金蝶要求财务在每张涉及现金的凭证上手工指定现金流量项目，漏指定就出不了表。
# 我们默认按**对方科目自动推断**（见 INFER_RULES），财务只在推断不对时手工覆盖——
# 存量凭证一张都不用回头补录，现金流量表直接能出。
module Erp::CashFlowItem
  OPERATING = 'OPERATING'.freeze
  INVESTING = 'INVESTING'.freeze
  FINANCING = 'FINANCING'.freeze

  SECTIONS = {
    OPERATING => '一、经营活动产生的现金流量',
    INVESTING => '二、投资活动产生的现金流量',
    FINANCING => '三、筹资活动产生的现金流量'
  }.freeze

  # 小计行用的短名：「经营活动产生的现金流量净额」。
  SHORT_LABELS = { OPERATING => '经营', INVESTING => '投资', FINANCING => '筹资' }.freeze

  INFLOW = 'IN'.freeze
  OUTFLOW = 'OUT'.freeze

  # 顺序即报表行序，与金蝶《会企03表》逐行一致（行次见 Erp::CashFlowService 的 row_no）。
  ITEMS = [
    { code: 'OP_IN_SALES', section: OPERATING, flow: INFLOW, label: '销售商品、提供劳务收到的现金' },
    { code: 'OP_IN_TAX_REFUND', section: OPERATING, flow: INFLOW, label: '收到的税费返还' },
    { code: 'OP_IN_OTHER', section: OPERATING, flow: INFLOW, label: '收到其他与经营活动有关的现金' },
    { code: 'OP_OUT_GOODS', section: OPERATING, flow: OUTFLOW, label: '购买商品、接受劳务支付的现金' },
    { code: 'OP_OUT_STAFF', section: OPERATING, flow: OUTFLOW, label: '支付给职工以及为职工支付的现金' },
    { code: 'OP_OUT_TAX', section: OPERATING, flow: OUTFLOW, label: '支付的各项税费' },
    { code: 'OP_OUT_OTHER', section: OPERATING, flow: OUTFLOW, label: '支付其他与经营活动有关的现金' },
    { code: 'INV_IN_RECOVER', section: INVESTING, flow: INFLOW, label: '收回投资收到的现金' },
    { code: 'INV_IN_RETURN', section: INVESTING, flow: INFLOW, label: '取得投资收益收到的现金' },
    { code: 'INV_IN_DISPOSAL', section: INVESTING, flow: INFLOW, label: '处置固定资产、无形资产和其他长期资产收回的现金净额' },
    { code: 'INV_IN_SUBSIDIARY', section: INVESTING, flow: INFLOW, label: '处置子公司及其他营业单位收到的现金净额' },
    { code: 'INV_IN_OTHER', section: INVESTING, flow: INFLOW, label: '收到其他与投资活动有关的现金' },
    { code: 'INV_OUT_CAPEX', section: INVESTING, flow: OUTFLOW, label: '购建固定资产、无形资产和其他长期资产支付的现金' },
    { code: 'INV_OUT_INVEST', section: INVESTING, flow: OUTFLOW, label: '投资支付的现金' },
    { code: 'INV_OUT_SUBSIDIARY', section: INVESTING, flow: OUTFLOW, label: '取得子公司及其他营业单位支付的现金净额' },
    { code: 'INV_OUT_OTHER', section: INVESTING, flow: OUTFLOW, label: '支付其他与投资活动有关的现金' },
    { code: 'FIN_IN_INVEST', section: FINANCING, flow: INFLOW, label: '吸收投资收到的现金' },
    { code: 'FIN_IN_LOAN', section: FINANCING, flow: INFLOW, label: '取得借款收到的现金' },
    { code: 'FIN_IN_OTHER', section: FINANCING, flow: INFLOW, label: '收到其他与筹资活动有关的现金' },
    { code: 'FIN_OUT_REPAY', section: FINANCING, flow: OUTFLOW, label: '偿还债务支付的现金' },
    { code: 'FIN_OUT_DIVIDEND', section: FINANCING, flow: OUTFLOW, label: '分配股利、利润或偿付利息支付的现金' },
    { code: 'FIN_OUT_OTHER', section: FINANCING, flow: OUTFLOW, label: '支付其他与筹资活动有关的现金' }
  ].freeze

  CODES = ITEMS.pluck(:code).freeze
  BY_CODE = ITEMS.index_by { |item| item[:code] }.freeze

  # 推断规则：现金分录的**对方科目编码前缀** → 现金流量项目。
  # 现金流入看 INFLOW_RULES（现金在借方），流出看 OUTFLOW_RULES（现金在贷方）。
  INFLOW_RULES = {
    '1121' => 'OP_IN_SALES', '1122' => 'OP_IN_SALES', '2203' => 'OP_IN_SALES',
    '6001' => 'OP_IN_SALES', '6021' => 'OP_IN_SALES',
    '2221' => 'OP_IN_TAX_REFUND',
    '1501' => 'INV_IN_RECOVER', '1101' => 'INV_IN_RECOVER',
    '1131' => 'INV_IN_RETURN', '1132' => 'INV_IN_RETURN', '6111' => 'INV_IN_RETURN', '6011' => 'INV_IN_RETURN',
    '1601' => 'INV_IN_DISPOSAL', '1606' => 'INV_IN_DISPOSAL', '1701' => 'INV_IN_DISPOSAL', '6115' => 'INV_IN_DISPOSAL',
    '2001' => 'FIN_IN_LOAN', '2501' => 'FIN_IN_LOAN', '2701' => 'FIN_IN_LOAN',
    '4001' => 'FIN_IN_INVEST', '4002' => 'FIN_IN_INVEST'
  }.freeze

  OUTFLOW_RULES = {
    '1123' => 'OP_OUT_GOODS', '1401' => 'OP_OUT_GOODS', '1402' => 'OP_OUT_GOODS', '1403' => 'OP_OUT_GOODS',
    '1405' => 'OP_OUT_GOODS', '1406' => 'OP_OUT_GOODS', '1408' => 'OP_OUT_GOODS',
    '2201' => 'OP_OUT_GOODS', '2202' => 'OP_OUT_GOODS',
    '5001' => 'OP_OUT_GOODS', '5101' => 'OP_OUT_GOODS', '5201' => 'OP_OUT_GOODS',
    '6401' => 'OP_OUT_GOODS', '6402' => 'OP_OUT_GOODS',
    '2211' => 'OP_OUT_STAFF', '660201' => 'OP_OUT_STAFF',
    '2221' => 'OP_OUT_TAX', '6403' => 'OP_OUT_TAX', '6801' => 'OP_OUT_TAX',
    '1604' => 'INV_OUT_CAPEX', '1601' => 'INV_OUT_CAPEX', '1701' => 'INV_OUT_CAPEX',
    '1101' => 'INV_OUT_INVEST', '1501' => 'INV_OUT_INVEST',
    '2001' => 'FIN_OUT_REPAY', '2501' => 'FIN_OUT_REPAY', '2701' => 'FIN_OUT_REPAY',
    '660301' => 'FIN_OUT_DIVIDEND', '2231' => 'FIN_OUT_DIVIDEND', '2232' => 'FIN_OUT_DIVIDEND', '4104' => 'FIN_OUT_DIVIDEND'
  }.freeze

  DEFAULT_INFLOW = 'OP_IN_OTHER'.freeze
  DEFAULT_OUTFLOW = 'OP_OUT_OTHER'.freeze

  class << self
    def label(code)
      BY_CODE.dig(code, :label)
    end

    def items_for_select
      ITEMS.map { |item| item.merge(section_label: SECTIONS[item[:section]]) }
    end

    # 对方科目编码 → 项目编码。取**最长匹配前缀**：660201（职工薪酬）要先于 6602（管理费用）命中。
    def infer(counterpart_code, inflow:)
      rules = inflow ? INFLOW_RULES : OUTFLOW_RULES
      hit = rules.keys.select { |prefix| counterpart_code.to_s.start_with?(prefix) }.max_by(&:length)
      return rules[hit] if hit

      inflow ? DEFAULT_INFLOW : DEFAULT_OUTFLOW
    end
  end
end
