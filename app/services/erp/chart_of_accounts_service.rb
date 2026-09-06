# 标准科目表初始化：把 lib/erp/cn_standard_coa.json（财政部国标编码）灌进 erp_ledger_accounts。
#
# 幂等：按 code 匹配，缺的建、已有的不动（用户改过的名称/维度/停用状态一律保留），
# 所以可以反复点「初始化标准科目表」补齐新增的预置科目，不会覆盖财务的手工调整。
# 建出来的科目打 is_system=true：允许改名/停用，禁止删除（模型 ensure_deletable 兜底）。
class Erp::ChartOfAccountsService
  TEMPLATE_PATH = Rails.root.join('lib/erp/cn_standard_coa.json')

  class << self
    def template
      @template ||= JSON.parse(File.read(TEMPLATE_PATH))
    end

    # 返回 { created:, existing:, total: }
    def ensure_standard!(account)
      created = 0
      existing = 0
      ActiveRecord::Base.transaction do
        walk(template['tree'], nil, nil, account) do |result|
          result == :created ? created += 1 : existing += 1
        end
      end
      { created: created, existing: existing, total: account.erp_ledger_accounts.count }
    end

    private

    def walk(nodes, parent_record, inherited, account, &)
      nodes.each_with_index do |node, index|
        attrs = node_attributes(node, inherited, index)
        record = account.erp_ledger_accounts.find_by(code: attrs[:code])
        if record.present?
          # 已存在：只补父子链（历史数据可能缺 parent），其余字段是财务的地盘，不覆盖。
          record.update!(parent_id: parent_record.id) if parent_record.present? && record.parent_id.blank?
          yield :existing
        else
          record = account.erp_ledger_accounts.create!(attrs.merge(parent_id: parent_record&.id))
          yield :created
        end

        next if node['children'].blank?

        walk(node['children'], record, { category: attrs[:category], direction: attrs[:direction] }, account, &)
      end
    end

    def node_attributes(node, inherited, index)
      category = node['category'] || inherited&.dig(:category)
      direction = node['direction'] || inherited&.dig(:direction)
      {
        code: node['code'],
        name: node['name'],
        category: category,
        direction: direction,
        is_group: node['is_group'].present? || node['children'].present?,
        account_type: node['account_type'],
        currency: node['currency'],
        bs_section: node['bs_section'],
        dimensions: node['dimensions'] || [],
        is_system: true,
        position: index,
        remark: node['remark']
      }
    end
  end
end
