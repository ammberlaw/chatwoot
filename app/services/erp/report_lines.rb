# 报表行式模板：资产负债表（会企01）/ 利润表（会企02）的固定行次与行名。
# 行次、行名与金蝶导出的那两张表逐字一致——财务两边对报表时不用再脑内换算哪一行对哪一行。
#
# 单独一个文件放这两张表的行式：它们是「报表长什么样」，和「怎么取数」（FinancialReportService）
# 是两回事，混在一个文件里会把取数逻辑埋在三百行常量后面。
module Erp::ReportLines # rubocop:disable Metrics/ModuleLength
  # ── 会企01 表（资产负债表）固定行式 ──
  # 行次、行名与金蝶导出的《会企01表》逐字一致，财务两边对报表不用再脑内换算。
  # prefixes 是归入该行的科目编码前缀（末级科目按前缀归集，备抵科目自动冲减）；
  # 账套里没有对应科目的行（合同资产、使用权资产…）照金蝶的样子留空行，不删。
  # sum 行是小计/合计，列出相加的行次；minus 列出要减掉的行次；
  # sub: true 是「其中：」的拆分行，已含在上一行里，不参与小计。
  BS_ASSET_LINES = [
    { heading: '流动资产：' },
    { no: 1, label: '货币资金', prefixes: %w[1001 1002 1012] },
    { no: 2, label: '交易性金融资产', prefixes: %w[1101] },
    { no: 3, label: '衍生金融资产', prefixes: [] },
    { no: 4, label: '应收票据', prefixes: %w[1121] },
    # 坏账准备(1231)是备抵科目，按借方常态值折算后自然是负数，这里跟应收账款同行冲减。
    { no: 5, label: '应收账款', prefixes: %w[1122 1231] },
    { no: 6, label: '应收款项融资', prefixes: [] },
    { no: 7, label: '预付款项', prefixes: %w[1123] },
    { no: 8, label: '其他应收款', prefixes: %w[1221 1131 1132] },
    { no: 9, label: '存货', prefixes: %w[14] },
    { no: 10, label: '合同资产', prefixes: [] },
    { no: 11, label: '持有待售资产', prefixes: [] },
    { no: 12, label: '一年内到期的非流动资产', prefixes: [] },
    { no: 13, label: '其他流动资产', prefixes: [] },
    { no: 14, label: '流动资产合计', sum: (1..13).to_a },
    { heading: '非流动资产：' },
    { no: 15, label: '债权投资', prefixes: [] },
    { no: 16, label: '其他债权投资', prefixes: [] },
    { no: 17, label: '长期应收款', prefixes: [] },
    { no: 18, label: '长期股权投资', prefixes: %w[1501] },
    { no: 19, label: '其他权益工具投资', prefixes: [] },
    { no: 20, label: '其他非流动金融资产', prefixes: [] },
    { no: 21, label: '投资性房地产', prefixes: [] },
    { no: 22, label: '固定资产', prefixes: %w[1601 1602 1603 1606] },
    { no: 23, label: '在建工程', prefixes: %w[1604] },
    { no: 24, label: '生产性生物资产', prefixes: [] },
    { no: 25, label: '油气资产', prefixes: [] },
    { no: 26, label: '使用权资产', prefixes: [] },
    { no: 27, label: '无形资产', prefixes: %w[1701 1702 1703] },
    { no: 28, label: '开发支出', prefixes: [] },
    { no: 29, label: '商誉', prefixes: [] },
    { no: 30, label: '长期待摊费用', prefixes: %w[1801] },
    { no: 31, label: '递延所得税资产', prefixes: %w[1811] },
    { no: 32, label: '其他非流动资产', prefixes: [] },
    { no: 33, label: '非流动资产合计', sum: (15..32).to_a },
    { no: 34, label: '资产总计', sum: [14, 33] }
  ].freeze

  BS_EQUITY_LINES = [
    { heading: '流动负债：' },
    { no: 35, label: '短期借款', prefixes: %w[2001] },
    { no: 36, label: '交易性金融负债', prefixes: [] },
    { no: 37, label: '衍生金融负债', prefixes: [] },
    { no: 38, label: '应付票据', prefixes: %w[2201] },
    { no: 39, label: '应付账款', prefixes: %w[2202] },
    { no: 40, label: '预收款项', prefixes: %w[2203] },
    { no: 41, label: '合同负债', prefixes: [] },
    { no: 42, label: '应付职工薪酬', prefixes: %w[2211] },
    { no: 43, label: '应交税费', prefixes: %w[2221] },
    { no: 44, label: '其他应付款', prefixes: %w[2241 2231 2232] },
    { no: 45, label: '持有待售负债', prefixes: [] },
    { no: 46, label: '一年内到期的非流动负债', prefixes: [] },
    { no: 47, label: '其他流动负债', prefixes: [] },
    { no: 48, label: '流动负债合计', sum: (35..47).to_a },
    { heading: '非流动负债：' },
    { no: 49, label: '长期借款', prefixes: %w[2501] },
    { no: 50, label: '应付债券', prefixes: [] },
    { no: 51, label: '其中：优先股', prefixes: [], sub: true },
    { no: 52, label: '永续债', prefixes: [], sub: true },
    { no: 53, label: '租赁负债', prefixes: [] },
    { no: 54, label: '长期应付款', prefixes: %w[2701] },
    { no: 55, label: '预计负债', prefixes: [] },
    { no: 56, label: '递延收益', prefixes: [] },
    { no: 57, label: '递延所得税负债', prefixes: %w[2901] },
    { no: 58, label: '其他非流动负债', prefixes: [] },
    { no: 59, label: '非流动负债合计', sum: [49, 50, 53, 54, 55, 56, 57, 58] },
    { no: 60, label: '负债合计', sum: [48, 59] },
    { heading: '所有者权益（或股东权益）：' },
    { no: 61, label: '实收资本（或股本）', prefixes: %w[4001] },
    { no: 62, label: '其他权益工具', prefixes: [] },
    { no: 63, label: '其中：优先股', prefixes: [], sub: true },
    { no: 64, label: '永续债', prefixes: [], sub: true },
    { no: 65, label: '资本公积', prefixes: %w[4002] },
    { no: 66, label: '减：库存股', prefixes: [] },
    { no: 67, label: '其他综合收益', prefixes: [] },
    { no: 68, label: '专项储备', prefixes: [] },
    { no: 69, label: '盈余公积', prefixes: %w[4101] },
    # 未分配利润含「本年利润尚未结转」那部分：期中没结转时，损益科目余额还挂着，
    # 不并进来资产负债表就不平（本年利润 4103 / 利润分配 4104 结转后才有数）。
    { no: 70, label: '未分配利润', prefixes: %w[4103 4104], with_current_profit: true },
    { no: 71, label: '所有者权益（或股东权益）合计', sum: [61, 62, 65, 67, 68, 69, 70], minus: [66] },
    { no: 72, label: '负债和所有者权益（或股东权益）总计', sum: [60, 71] }
  ].freeze

  # ── 会企02 表（利润表）固定行式 ──
  # 同样逐字对齐金蝶。prefixes 为空的行是账套里没有对应科目的（研发费用、信用减值损失、
  # 其他综合收益那一整段…），留空行不删——金蝶导出来也是空的。
  # key 给小计行引用；sub: true 是「其中：」拆分行，已含在上一行里。
  INCOME_LINES = [
    { no: 1, key: 'revenue', label: '一、营业收入', prefixes: %w[6001 6021], sign: :credit },
    { no: 2, key: 'cost', label: '减：营业成本', prefixes: %w[6401 6402], sign: :debit },
    { no: 3, key: 'tax_surcharge', label: '税金及附加', prefixes: %w[6403], sign: :debit, indent: 1 },
    { no: 4, key: 'selling', label: '销售费用', prefixes: %w[6601], sign: :debit, indent: 1 },
    { no: 5, key: 'admin', label: '管理费用', prefixes: %w[6602], sign: :debit, indent: 1 },
    { no: 6, key: 'rd', label: '研发费用', prefixes: %w[6604], sign: :debit, indent: 1 },
    { no: 7, key: 'finance', label: '财务费用', prefixes: %w[6603], sign: :debit, indent: 1 },
    { no: 8, key: 'interest_expense', label: '其中：利息费用', prefixes: %w[660301], sign: :debit, indent: 2, sub: true },
    { no: 9, key: 'interest_income', label: '利息收入', prefixes: %w[6011], sign: :credit, indent: 2 },
    { no: 10, key: 'impairment', label: '资产减值损失', prefixes: %w[6701 6702], sign: :debit, indent: 1 },
    { no: 11, key: 'credit_impairment', label: '信用减值损失', prefixes: [], sign: :debit, indent: 1 },
    { no: 12, key: 'other_income', label: '加：其他收益', prefixes: %w[6051], sign: :credit },
    { no: 13, key: 'investment', label: '投资收益（损失以“-”号填列）', prefixes: %w[6111], sign: :credit, indent: 1 },
    { no: 14, key: 'investment_joint', label: '其中：对联营企业和合营企业的投资收益', prefixes: [], sign: :credit, indent: 2, sub: true },
    { no: 15, key: 'amortized_cost_gain', label: '以摊余成本计量的金融资产终止确认收益（损失以“-”号填列）', prefixes: [], sign: :credit, indent: 2 },
    { no: 16, key: 'net_hedge', label: '净敞口套期收益（损失以“-”号填列）', prefixes: [], sign: :credit, indent: 2 },
    { no: 17, key: 'fair_value', label: '公允价值变动收益（损失以“-”号填列）', prefixes: [], sign: :credit, indent: 2 },
    { no: 18, key: 'asset_disposal', label: '资产处置收益（损失以“-”号填列）', prefixes: %w[6115], sign: :credit, indent: 2 },
    { no: 19, key: 'operating_profit', label: '二、营业利润（亏损以“-”号填列）',
      sum: %w[revenue other_income investment amortized_cost_gain net_hedge fair_value asset_disposal interest_income],
      minus: %w[cost tax_surcharge selling admin rd finance impairment credit_impairment] },
    { no: 20, key: 'non_operating_income', label: '加：营业外收入', prefixes: %w[6301], sign: :credit },
    { no: 21, key: 'non_operating_expense', label: '减：营业外支出', prefixes: %w[6711], sign: :debit },
    { no: 22, key: 'total_profit', label: '三、利润总额（亏损总额以“-”号填列）',
      sum: %w[operating_profit non_operating_income], minus: %w[non_operating_expense] },
    { no: 23, key: 'income_tax', label: '减：所得税费用', prefixes: %w[6801], sign: :debit },
    { no: 24, key: 'net_profit', label: '四、净利润（净亏损以“-”号填列）', sum: %w[total_profit], minus: %w[income_tax] },
    { no: 25, key: 'net_profit_going', label: '（一）持续经营净利润（净亏损以“-”号填列）', prefixes: [], sign: :credit, indent: 1 },
    { no: 26, key: 'net_profit_discontinued', label: '（二）终止经营净利润（净亏损以“-”号填列）', prefixes: [], sign: :credit, indent: 1 },
    { no: 27, key: 'oci', label: '五、其他综合收益的税后净额', prefixes: [], sign: :credit },
    { no: 28, label: '（一）不能重分类进损益的其他综合收益', prefixes: [], sign: :credit, indent: 1 },
    { no: 29, label: '1．重新计量设定受益计划变动额', prefixes: [], sign: :credit, indent: 2 },
    { no: 30, label: '2．权益法下不能转损益的其他综合收益', prefixes: [], sign: :credit, indent: 2 },
    { no: 31, label: '3．其他权益工具投资公允价值变动', prefixes: [], sign: :credit, indent: 2 },
    { no: 32, label: '4．企业自身信用风险公允价值变动', prefixes: [], sign: :credit, indent: 2 },
    { no: 33, label: '……', prefixes: [], sign: :credit, indent: 2 },
    { no: 34, label: '（二）将重分类进损益的其他综合收益', prefixes: [], sign: :credit, indent: 1 },
    { no: 35, label: '1．权益法下可转损益的其他综合收益', prefixes: [], sign: :credit, indent: 2 },
    { no: 36, label: '2．其他债权投资公允价值变动', prefixes: [], sign: :credit, indent: 2 },
    { no: 37, label: '3．金融资产重分类计入其他综合收益的金额', prefixes: [], sign: :credit, indent: 2 },
    { no: 38, label: '4．其他债权投资信用减值准备', prefixes: [], sign: :credit, indent: 2 },
    { no: 39, label: '5．现金流量套期储备', prefixes: [], sign: :credit, indent: 2 },
    { no: 40, label: '6．外币财务报表折算差额', prefixes: [], sign: :credit, indent: 2 },
    { no: 41, label: '……', prefixes: [], sign: :credit, indent: 2 },
    { no: 42, key: 'comprehensive_income', label: '六、综合收益总额', sum: %w[net_profit oci] },
    { no: 43, label: '七、每股收益：', prefixes: [], sign: :credit },
    { no: 44, label: '（一）基本每股收益', prefixes: [], sign: :credit, indent: 1 },
    { no: 45, label: '（二）稀释每股收益', prefixes: [], sign: :credit, indent: 1 }
  ].freeze
end
