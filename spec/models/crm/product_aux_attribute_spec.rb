# frozen_string_literal: true

require 'rails_helper'

# 辅助属性：同一物料编码下的可选变体。编码照金蝶口径自动生成，
# 已被单据选过的不能物理删除（历史单据会失去来历）。
RSpec.describe Crm::ProductAuxAttribute do
  let(:account) { create(:account) }
  let(:product) { account.crm_products.create!(name: '327090电池', sku: 'P.07.009') }

  def add(name)
    product.aux_attributes.create!(account_id: account.id, name: name)
  end

  it '编码按 <物料编码>_<三位序号> 自动生成，依次递增' do
    expect([add('喷码6000').code, add('喷码3500').code, add('喷码4000').code])
      .to eq(['P.07.009_001', 'P.07.009_002', 'P.07.009_003'])
  end

  # 能被物理删除的必然是「从没被任何单据选过」的（被选过的只停用、行还留着，
  # 序号照样占位），所以回收空出来的序号不会和历史单据撞上。
  it '删掉从未被引用的属性后，序号回收复用' do
    add('喷码6000')
    add('喷码3500').destroy!
    expect(add('喷码4000').code).to eq('P.07.009_002')
  end

  it '停用的属性仍占着序号，新建接在它后面' do
    add('喷码6000')
    add('喷码3500').update!(is_active: false)
    expect(add('喷码4000').code).to eq('P.07.009_003')
  end

  it '同一账号下编码唯一' do
    add('喷码6000')
    dup = product.aux_attributes.new(account_id: account.id, name: '重复', code: 'P.07.009_001')
    expect(dup).not_to be_valid
  end

  it '产品删除时属性跟着走' do
    add('喷码6000')
    expect { product.destroy! }.to change(described_class, :count).by(-1)
  end

  it '只列启用中的（停用的留在库里供历史单据追溯）' do
    add('喷码6000')
    add('喷码3500').update!(is_active: false)
    expect(product.aux_attributes.active.pluck(:name)).to eq(['喷码6000'])
  end
end
