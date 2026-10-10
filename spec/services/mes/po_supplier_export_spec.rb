require 'rails_helper'
require 'zip'
RSpec.describe Mes::PoSupplierExport do
  let(:account) { create(:account) }
  let(:supplier) { account.mes_suppliers.create!(name: '验收供应商', tax_rate: tax, bill_entity: entity, product_line: 'TABLET') }
  let(:po) { account.mes_purchase_orders.create!(product_line: 'DISPLAY') }
  let(:item) { po.purchase_items.create!(mes_supplier: supplier, qty: quantity, rate_micros: rate, price_tax_included: included) }

  [[13, false, 'liontek'], [13, true, 'liontek'], [13, true, 'wintouch'], [6, false, 'liontek'],
   [0, false, 'liontek'], [13, false, 'liontek', 10_123_456, '3.125'],
   [13, true, 'wintouch', 10_123_456, '3.125']].each do |tax_value, included_value, entity_value, rate_value, qty_value|
    context "with tax=#{tax_value}, included=#{included_value}, entity=#{entity_value}" do
      let(:tax) { tax_value }
      let(:included) { included_value }
      let(:entity) { entity_value }
      let(:rate) { rate_value || 113_000_000 }
      let(:quantity) { qty_value || 3 }

      it 'preview price and amount match the actual exported spreadsheet' do
        item
        row = described_class.new(po).payload[:suppliers].first[:items].first
        bytes = Mes::PoTemplateFiller.new(supplier: supplier, items: [item], purchase_order: po).to_stream
        sheet = nil
        Zip::File.open_buffer(bytes) { |z| sheet = Nokogiri::XML(z.read('xl/worksheets/sheet1.xml')).remove_namespaces! }
        price_cell, amount_cell = entity == 'liontek' ? %w[I8 J8] : %w[J9 L9]
        price = sheet.at_xpath("//c[@r='#{price_cell}']/v").text.to_f
        amount = sheet.at_xpath("//c[@r='#{amount_cell}']/v").text.to_f
        expect({ price: row[:price], amount: row[:amount] }).to eq({ price: price, amount: amount })
      end
    end
  end
end
