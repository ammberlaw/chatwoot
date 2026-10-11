# frozen_string_literal: true

require 'rails_helper'

# 固定资产批量导入（期初建账）。
#
# 要点不是「能导进来」，是**已提折旧必须带得进来**：历史资产不带累计折旧，系统会从零
# 重新提一遍，折旧费用和净值全错，而这种错不报警。
# 另外填了部门/保管人却对不上的行必须退回来——静默置空等于悄悄丢掉归属。
RSpec.describe Erp::FixedAssetImportService do
  let(:account) { create(:account) }
  let(:keeper) { create(:user, account: account, name: '张三') }

  let(:header) do
    %w[资产编码 资产名称 类别 购入日期 原值 残值率 折旧月数 已提折旧 使用部门 保管人 备注]
  end

  # 用仓库自带的 XlsxWriter 现造一个 xlsx 给 roo 读，不往 spec 里塞二进制夹具。
  def xlsx_with(rows)
    sheet_rows = [header.map { |text| [text, :s, :header] }] +
                 rows.map { |row| row.map { |cell| [cell.to_s, :s, :text] } }
    stream = XlsxWriter.new(col_widths: header.map { 14 }, rows: sheet_rows, sheet_name: '固定资产').to_stream
    file = Tempfile.new(['assets', '.xlsx'])
    file.binmode
    file.write(stream.read)
    file.flush
    file.path
  end

  def import(rows)
    described_class.new(account: account, path: xlsx_with(rows)).import!
  end

  it '把原值与期初已提折旧一起建进来，月折旧按直线法算' do
    result = import([['FA-001', 'SMT 贴片机', '生产设备', '2024-03-15', '480000', '5', '120', '96000', '', '', '']])

    expect(result).to include(rows: 1, created: 1)
    asset = account.erp_fixed_assets.find_by(asset_no: 'FA-001')
    expect(asset.original_value_micros).to eq(480_000_000_000)
    expect(asset.accumulated_depreciation_micros).to eq(96_000_000_000)
    # 可折旧 480000×95% = 456000，120 个月 → 每月 3800
    expect(asset.monthly_depreciation_micros).to eq(3_800_000_000)
    expect(asset.net_value_micros).to eq(384_000_000_000)
  end

  it '资产编码留空时自动编号' do
    import([['', '办公电脑', '电子设备', '2026-01-10', '6000', '', '', '', '', '', '']])

    expect(account.erp_fixed_assets.first.asset_no).to be_present
  end

  it '残值率与折旧月数留空用默认值（5% / 60 个月）' do
    import([['', '办公桌', '办公家具', '2026-01-10', '3000', '', '', '', '', '', '']])

    asset = account.erp_fixed_assets.first
    expect(asset.residual_rate).to eq(5)
    expect(asset.useful_months).to eq(60)
  end

  it '保管人按姓名对上人' do
    keeper
    import([['', '测试车', '车辆', '2025-05-01', '120000', '', '', '', '', '张三', '']])

    expect(account.erp_fixed_assets.first.keeper_id).to eq(keeper.id)
  end

  it '保管人对不上时这一行退回，不静默置空' do
    result = import([['', '测试车', '车辆', '2025-05-01', '120000', '', '', '', '', '查无此人', '']])

    expect(result[:created]).to eq(0)
    expect(result[:failed].first[:errors].first).to include('保管人「查无此人」')
    expect(account.erp_fixed_assets.count).to eq(0)
  end

  it '已提折旧超过可折旧总额时退回（否则净值低于残值，往后计提是负数）' do
    result = import([['', '超额资产', '生产设备', '2024-01-01', '100000', '5', '60', '99000', '', '', '']])

    expect(result[:created]).to eq(0)
    expect(result[:failed].first[:errors].first).to include('已提折旧超过')
  end

  it '类别写了不认识的词时退回并列出可选项' do
    result = import([['', '怪东西', '飞机', '2025-01-01', '100', '', '', '', '', '', '']])

    expect(result[:failed].first[:errors].first).to include('类别「飞机」不认识')
  end

  it '一行错不影响其它行，错误行带行号报回来' do
    result = import([
                      ['', '好资产', '生产设备', '2025-01-01', '10000', '', '', '', '', '', ''],
                      ['', '坏资产', '生产设备', '不是日期', '10000', '', '', '', '', '', ''],
                      ['', '也是好的', '办公家具', '2025-02-01', '2000', '', '', '', '', '', '']
                    ])

    expect(result).to include(rows: 3, created: 2)
    expect(result[:failed].size).to eq(1)
    expect(result[:failed].first[:row]).to eq(3) # 表头占第 1 行
    expect(result[:failed].first[:name]).to eq('坏资产')
  end

  it '原值是 0 或空的行退回' do
    result = import([['', '零元资产', '其他', '2025-01-01', '0', '', '', '', '', '', '']])

    expect(result[:failed].first[:errors].first).to include('原值必须大于 0')
  end

  it '资产编码与已有资产重复时退回，不覆盖原有档案' do
    account.erp_fixed_assets.create!(asset_no: 'FA-100', name: '老设备', category: 'EQUIPMENT',
                                     purchased_at: Date.new(2020, 1, 1), original_value_micros: 1_000_000)
    result = import([['FA-100', '新设备', '生产设备', '2026-01-01', '2000', '', '', '', '', '', '']])

    expect(result[:created]).to eq(0)
    expect(account.erp_fixed_assets.find_by(asset_no: 'FA-100').name).to eq('老设备')
  end

  it '没有数据行时直接报错，不是静默成功' do
    expect { import([]) }.to raise_error(described_class::Error, /没有数据行/)
  end

  it '模板能被自己的导入流程读回来（表头对得上）' do
    file = Tempfile.new(['tpl', '.xlsx'])
    file.binmode
    file.write(described_class.template_stream.read)
    file.flush

    result = described_class.new(account: account, path: file.path).import!

    expect(result[:created]).to eq(1)
    expect(account.erp_fixed_assets.first.name).to eq('SMT 贴片机')
  end
end
