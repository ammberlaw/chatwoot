require 'rails_helper'
require 'zip'

RSpec.describe Mes::PoTemplateFiller do
  let(:account) { create(:account) }
  let(:po) { account.mes_purchase_orders.create!(product_line: 'DISPLAY', delivery_date: '2026-10-15') }
  let(:supplier) { account.mes_suppliers.create!(name: '验收供应商', bill_entity: entity, tax_rate: 13, product_line: 'TABLET') }
  let(:item) { po.purchase_items.create!(mes_supplier: supplier, qty: 3, rate_micros: 10_000_000) }
  let(:entries) do
    result = {}
    stream = described_class.new(supplier: supplier, items: [item], purchase_order: po).to_stream
    Zip::File.open_buffer(stream) { |zip| zip.each { |entry| result[entry.name] = entry.get_input_stream.read } }
    result
  end
  let(:strings) { Nokogiri::XML(entries.fetch('xl/sharedStrings.xml')).remove_namespaces! }
  let(:sheet) { Nokogiri::XML(entries.fetch('xl/worksheets/sheet1.xml')).remove_namespaces! }
  let(:styles) { Nokogiri::XML(entries.fetch('xl/styles.xml')).remove_namespaces! }

  %w[liontek wintouch].each do |bill_entity|
    context bill_entity do
      let(:entity) { bill_entity }

      it 'uses the order delivery date while preserving the rich text formatting' do
        clause = strings.xpath('//si').find { |si| si.text.include?('交货时间、地点') }
        expect(clause.text).to include('2026年10月15日')
        expect(clause.text).not_to match(/2026年(?:4月2日|7月11日)/)
        expect(clause.xpath('./r/rPr/u')).not_to be_empty
      end

      it 'does not retain the sample date when delivery is undecided' do
        po.update!(delivery_date: nil)
        clause = strings.xpath('//si').find { |si| si.text.include?('交货时间、地点') }
        expect(clause.text).to include('待确认')
        expect(clause.text).not_to match(/\d{4}年\d+月\d+日/)
      end

      it 'formats prices with fractional precision and amounts with two decimals' do
        price_ref, amount_ref = entity == 'liontek' ? %w[I8 J8] : %w[J9 L9]
        price_style = styles.xpath('//cellXfs/xf')[sheet.at_xpath("//c[@r='#{price_ref}']")['s'].to_i]
        number_format = styles.at_xpath("//numFmt[@numFmtId='#{price_style['numFmtId']}']")
        expect(number_format['formatCode']).to eq('0.00####')
        amount_style = styles.xpath('//cellXfs/xf')[sheet.at_xpath("//c[@r='#{amount_ref}']")['s'].to_i]
        expect(amount_style['numFmtId']).to eq('2')
        if entity == 'liontek'
          total_style = styles.xpath('//cellXfs/xf')[sheet.at_xpath("//c[@r='J9']")['s'].to_i]
          expect(total_style['numFmtId']).to eq('2')
          expect(sheet.at_xpath("//c[@r='I8']/v").text.to_d).to eq(BigDecimal('11.3'))
          expect(sheet.at_xpath("//c[@r='J8']/v").text.to_d).to eq(BigDecimal('33.9'))
        end
      end
    end
  end
end
