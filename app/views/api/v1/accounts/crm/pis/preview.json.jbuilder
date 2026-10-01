# PI 在线预览：单据本体 + 导出时才解析的公司抬头/银行信息，供前端 1:1 排版。
json.partial! 'api/v1/models/crm_pi', formats: [:json], resource: @pi

json.company do
  json.name @header[:name]
  json.address @header[:address]
  json.beneficiary @header[:beneficiary]
  json.account_line @account_line
  json.bank @header[:bank]
  json.swift @header[:swift]
  json.bank_address @header[:bank_address]
  json.footer "#{@header[:footer]}#{@footer_suffix}"
end

# 与导出的 GRAND TOTAL 同一算法（各项金额 + 运费），不用 total_amount_micros。
json.grand_total_micros @grand_total_micros

json.seller do
  json.contact_line "Contact: #{@pi.issued_by}   |   Mobile: #{@pi.seller_mobile}"
  json.email_line "Email: #{@pi.seller_email}   |   #{@seller_web}"
end

# 条款按行拆好（导出里第一条单独一格、其余挤在下一格），预览逐条列出即可。
json.term_lines @pi.terms.to_s.split("\n").map(&:strip).reject(&:empty?)
