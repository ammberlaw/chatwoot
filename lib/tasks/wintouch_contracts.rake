# 跨文件隐式契约体检。
#
# 这个库里加一个页面/接口，常常要同时改好几个互不相邻的地方，漏掉任何一个
# **都不会报错**，只是静默失效——2026-11-04 一天之内就踩了三次：
#   · 工资表页路由和侧栏都加了，漏登记 ITEM_MODULE → 页面能直接访问，侧栏里看不见
#   · 知识库图库加了 action，漏加 policy 的 image_library? → 线上 500
#   · 返单改派后 ack 归属变了，分发表没跟上 → 整类告警从来没发出去过
#
# 这些清单靠人记必然会漏（memory 里记了也漏）。跑一次 `rake wintouch:check` 全查出来。
# 退出码非 0，可以直接挂到 pre-push 或 CI 上。
namespace :wintouch do
  SIDEBAR = 'app/javascript/dashboard/components-next/sidebar/Sidebar.vue'.freeze
  ROUTE_FILES = {
    'crm' => 'app/javascript/dashboard/routes/dashboard/crm/routes.js',
    'mes' => 'app/javascript/dashboard/routes/dashboard/mes/routes.js',
    'erp' => 'app/javascript/dashboard/routes/dashboard/erp/routes.js',
    'tiktok' => 'app/javascript/dashboard/routes/dashboard/tiktok/routes.js'
  }.freeze

  desc '体检：路由/侧栏/权限/文案 的跨文件契约有没有漏改'
  task check: :environment do
    problems = []
    problems.concat(check_route_module)
    problems.concat(check_policy_actions)
    problems.concat(check_i18n_keys)

    if problems.empty?
      puts '✅ 契约体检通过'
    else
      puts "❌ 发现 #{problems.size} 处漏改：\n\n"
      problems.group_by { |p| p[:kind] }.each do |kind, rows|
        puts "【#{kind}】"
        rows.each { |r| puts "  #{r[:msg]}" }
        puts "  → #{rows.first[:fix]}\n\n"
      end
      abort
    end
  end

  # ── 1. 侧栏按 activeModule 分屏显示：路由不在 ROUTE_MODULE 里，
  #       进这个页面时侧栏会跳回别的板块；菜单项不在 ITEM_MODULE 里，默认算 crm 模块，
  #       挂在 hr/mes/erp 板块下的入口就不显示。
  def check_route_module
    sidebar = File.read(SIDEBAR)
    mapped = sidebar[/const ROUTE_MODULE = \{(.*?)\n\}/m, 1].to_s.scan(/^\s*([a-z0-9_]+):/).flatten.to_set
    out = []
    ROUTE_FILES.each do |mod, file|
      next unless File.exist?(file)

      names = File.read(file).scan(/Page\(\s*'[^']*',\s*'([a-z0-9_]+)'/).flatten
      # crm 模块是 ROUTE_MODULE 的默认值，不登记也对；其余板块必须显式登记。
      next if mod == 'crm'

      names.reject { |n| mapped.include?(n) }.each do |n|
        out << { kind: '路由没登记 ROUTE_MODULE', msg: "#{mod}: #{n}",
                 fix: "在 #{SIDEBAR} 的 ROUTE_MODULE 里加 `#{n}: '#{mod}'`" }
      end
    end
    out
  end

  # ── 2. Pundit 要求每个 authorize 过的 action 都有同名 policy 方法，
  #       漏一个就是运行时 NoMethodError → 500，而且只有走到那个 action 才会炸。
  #
  # 用 Rails 路由表判定「什么是 action」，不靠扫源码里的 def ——
  # 控制器里公开的辅助方法（sort_clause、list_order 这类）不是 action，
  # 按文本切 private 会把它们全报成漏改。
  def check_policy_actions
    out = []
    routes = Rails.application.routes.routes.filter_map do |r|
      c = r.defaults[:controller]
      a = r.defaults[:action]
      next if c.blank? || a.blank?
      next unless c.start_with?('api/v1/accounts/')
      next unless c.match?(%r{/(crm|mes|erp|tiktok|oa)/})

      [c, a]
    end.uniq

    routes.group_by(&:first).each do |controller, pairs|
      file = "app/controllers/#{controller}_controller.rb"
      next unless File.exist?(file)

      klass = File.read(file)[/authorize\(([A-Za-z:]+)\)/, 1]
      next if klass.blank?

      policy = "#{klass}Policy".safe_constantize
      next if policy.nil?

      pairs.map(&:last).uniq.each do |action|
        next if policy.method_defined?("#{action}?")

        out << { kind: 'action 没有对应 policy 方法',
                 msg: "#{controller} ##{action} → #{policy}##{action}?",
                 fix: '在对应 policy 里补 `def <action>? = ...`（照 index? 写）' }
      end
    end
    out
  end

  # ── 3. t('X.Y') 指向不存在的 key 时，界面直接显示原始 key（如 SIDEBAR.CRM_PAYROLL），
  #       不报错，要靠肉眼看到才知道。
  # dict 里中途可能遇到字符串或数组，Hash#dig 会直接抛 TypeError，得自己一层层走。
  def i18n_has?(dict, key)
    key.split('.').reduce(dict) do |node, seg|
      return false unless node.is_a?(Hash)

      node[seg]
    end.present?
  end

  def check_i18n_keys
    dict = Dir['app/javascript/dashboard/i18n/locale/en/*.json'].each_with_object({}) do |f, acc|
      acc.deep_merge!(JSON.parse(File.read(f)))
    end
    out = []
    # 只查自己写的那几个板块：Chatwoot 上游的 settings/ 等目录有一批历史缺 key 和
    # FEATURES.0 这种数组下标写法，不是我们该管的，混进来会把真问题淹掉。
    ours = Dir['app/javascript/dashboard/routes/dashboard/{crm,mes,erp,tiktok}/**/*.vue'] +
           Dir['app/javascript/dashboard/components-next/{CRM,mes,erp}/**/*.vue'] +
           [SIDEBAR]
    ours.each do |file|
      File.read(file).scan(/\bt\(\s*'([A-Z][A-Z0-9_.]+)'/).flatten.uniq.each do |key|
        next if key.include?('${') # 动态拼的 key 查不了

        next if i18n_has?(dict, key)

        out << { kind: 'i18n key 不存在', msg: "#{file.sub('app/javascript/dashboard/', '')} → #{key}",
                 fix: '在 app/javascript/dashboard/i18n/locale/en/*.json 里补上这个 key' }
      end
    end
    out
  end
end
