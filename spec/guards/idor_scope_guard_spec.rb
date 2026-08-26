# 不变量守卫（纯静态扫描，不 boot Rails/无需 DB）：敏感 CRM 记录不得按 id 裸取。
#
# 背景：客户/PI/报价单/报价明细/销售目标/联系人的 before_action fetch 若写成
# Current.account.crm_xxx.find(params[:id])（不经可见范围收口），则任意业务员改 URL 里的
# id 就能读改他人记录（IDOR）。修复口径：客户/联系人经 visible_customers，PI/报价经
# scope_docs_visible，销售目标经 scope_by_owner 收口后再 .find。此守卫防同类回归。
RSpec.describe 'CRM IDOR scope guard' do
  repo_root = File.expand_path('../..', __dir__)
  controllers_dir = File.join(repo_root, 'app/controllers/api/v1/accounts/crm')

  # 敏感取法（Current.account.<assoc>.find(params[:id])）=> 说明。
  sensitive = {
    /Current\.account\.crm_customers\.find\(params\[:id\]\)/ => 'crm_customers',
    /Current\.account\.crm_pis\.find\(params\[:id\]\)/ => 'crm_pis',
    /Current\.account\.crm_quotes\.find\(params\[:id\]\)/ => 'crm_quotes',
    /Current\.account\.crm_quote_line_items\.find\(params\[:id\]\)/ => 'crm_quote_line_items',
    /Current\.account\.crm_sales_targets\.find\(params\[:id\]\)/ => 'crm_sales_targets',
    /Current\.account\.contacts\.find\(params\[:id\]\)/ => 'contacts(crm)'
  }

  sensitive.each do |pattern, label|
    it "#{label} 不得按 id 裸取（须经可见范围收口，防 IDOR）" do
      offenders = Dir.glob(File.join(controllers_dir, '*.rb')).select do |file|
        File.read(file).match?(pattern)
      end.map { |f| f.sub("#{repo_root}/", '') }

      expect(offenders).to be_empty,
                           "以下控制器按 id 裸取 #{label}，可被越权读改（IDOR）：\n" \
                           "#{offenders.map { |f| "  - #{f}" }.join("\n")}\n" \
                           '改为经 visible_customers / scope_docs_visible / scope_by_owner 收口后再 .find。'
    end
  end
end
