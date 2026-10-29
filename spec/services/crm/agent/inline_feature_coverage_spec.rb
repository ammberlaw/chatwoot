require 'rails_helper'

# AI 助手得知道新功能存在，否则用户问「XX 在哪」它答不出来或者瞎猜。
#
# 为什么要这个闸：隔壁 system_map_spec 只拿 Sidebar.vue 的**菜单项**对一遍。
# 而「有没有 XX 功能」答错，十次有八次错在**藏在页面里的按钮**上——它不是菜单项，
# 菜单对账一路绿灯。2026-10-29 一天加了 13 个内嵌功能（日记账导入、制造费用分摊、
# 采购退料推料…），闸全没响，是用户问「这些都加进 agent 了吗」才发现。
#
# 这是个**棘轮**，不是全量检查：存量 144 条一次性收进 baseline，之后只拦新冒出来的。
# 新按钮要么写进 SystemMap，要么进 baseline 并写明为什么不用写。
describe 'AI 助手对内嵌功能的覆盖' do
  # 通用动作不算「功能」，用户不会问「保存在哪」。
  GENERIC_LABELS = %w[
    保存 删除 编辑 查看 关闭 查询 驳回 作废 取消 打印 过账 搜索 提交 通过 刷新 新增 新建
    加一行 存草稿 下发 试算 审核通过 恢复默认列序 导出图片 删单 停用 启用 确认 返回 上一页 下一页
    导出 导出\ Excel 全选 清空 重置 筛选 展开 收起 复制 上传 下载 选择 应用 继续 完成 更多
  ].freeze

  PAGE_GLOBS = %w[
    app/javascript/dashboard/routes/dashboard/mes/pages/*.vue
    app/javascript/dashboard/routes/dashboard/erp/pages/*.vue
  ].freeze

  # label="xxx" 里的静态中文文案。带 {{ }} 或三元表达式的跳过——那是动态文案，
  # 静态扫不出可靠结果，强扫只会制造误报。
  def button_labels
    PAGE_GLOBS.flat_map { |glob| Dir[Rails.root.join(glob)] }.flat_map do |path|
      File.read(path).scan(/label="([^"{}?:]+)"/).flatten
    end.map(&:strip).select { |t| t.match?(/\p{Han}/) }.uniq
  end

  let(:baseline) do
    YAML.load_file(Rails.root.join('spec/fixtures/agent_inline_feature_baseline.yml'))['baseline']
  end
  let(:system_map_text) { File.read(Rails.root.join('app/services/crm/agent/system_map.rb')) }

  it '界面上新加的按钮，要么写进 SystemMap，要么进基线并说明理由' do
    undocumented = button_labels - GENERIC_LABELS
    undocumented = undocumented.reject { |label| system_map_text.include?(label) }
    newcomers = undocumented - baseline

    expect(newcomers).to be_empty, <<~MSG
      这些按钮 AI 助手不知道，用户问「它在哪」会答不出来：
        #{newcomers.join("\n  ")}

      二选一：
        · 用户会问的 → 写进 Crm::Agent::SystemMap 的 INLINE，
          连路径和限制一起写（「财务管理 → 资金账户 → 右上角；当月没凭证就是灰的」）
        · 用户不会问的（行内操作、弹窗按钮）→ 加进
          spec/fixtures/agent_inline_feature_baseline.yml 并在行尾写明理由
    MSG
  end

  it '基线只收还没文档化的，写进 SystemMap 之后要从基线里删掉' do
    stale = baseline.select { |label| system_map_text.include?(label) }

    expect(stale).to be_empty,
                     "这些已经写进 SystemMap 了，把它们从 baseline 里删掉：\n  #{stale.join("\n  ")}"
  end
end
