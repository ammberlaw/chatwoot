require 'rails_helper'

# 这份 spec 的唯一目的：不让功能地图悄悄过期。
#
# 地图是喂给 AI 助手的「系统长什么样」，错一条，用户照着跑一趟空，
# 比没有地图更伤信任。左侧栏加了菜单却忘了更地图，这里会红。
RSpec.describe Crm::Agent::SystemMap do
  SIDEBAR_VUE = Rails.root.join('app/javascript/dashboard/components-next/sidebar/Sidebar.vue')
  SIDEBAR_I18N = Rails.root.join('app/javascript/dashboard/i18n/locale/en/settings.json')

  # 注释掉的菜单项不算——界面上没有的东西写进地图就是指错路。
  def sidebar_labels
    labels = JSON.parse(SIDEBAR_I18N.read)['SIDEBAR']
    src = SIDEBAR_VUE.read.lines.reject { |line| line.lstrip.start_with?('//') }.join

    keyed = src.scan(/label:\s*t\('SIDEBAR\.([A-Z_0-9]+)'\)/).flatten.filter_map { |k| labels[k] }
    literal = src.scan(/label:\s*'([^']+)'/).flatten

    # 中文的才是我们自己的板块；上游 Chatwoot 那些英文项（Captain/Campaigns…）不归这份地图管。
    (keyed + literal).uniq.select { |label| label.match?(/\p{Han}/) }
  end

  it '把左侧栏每一个中文菜单项都写进了地图' do
    missing = sidebar_labels.reject { |label| described_class.text.include?(label) }

    expect(missing).to be_empty,
                       -> { "左侧栏有这些菜单，功能地图里没有（加菜单时请同步 system_map.rb）：\n  #{missing.join("\n  ")}" }
  end

  it '地图正文塞得进一轮提示词' do
    # 这东西每一轮对话都要发一遍，失控了就是每条消息都在烧钱。
    expect(described_class.text.length).to be < 4000
  end

  # ROUTE_LABEL 管的是另一件事：用户此刻**站在哪一页**（见 Prompt.page_hint）。
  # 漏一条，助手在那页上就不知道他在看什么——2026-10-30 实测漏了 8 个，
  # 其中包括客户列表和客户详情这两个最常用的页面。
  CRM_ROUTES = Rails.root.join('app/javascript/dashboard/routes/dashboard/crm/routes.js')
  MES_ROUTES = Rails.root.join('app/javascript/dashboard/routes/dashboard/mes/routes.js')
  # 搁置未上线的功能故意不写进来：地图指向一个进不去的页面比不指更糟。
  INTENTIONALLY_UNLABELLED = %w[crm_exhibitions_index].freeze

  it '每一个 CRM/MES 页面都在 ROUTE_LABEL 里有个人话名字' do
    names = [CRM_ROUTES, MES_ROUTES].flat_map do |file|
      next [] unless file.exist?

      file.read.scan(/(?:crmPage|mesPage)\(\s*'[^']+',\s*'([a-z0-9_]+)'/).flatten
    end.uniq - INTENTIONALLY_UNLABELLED

    missing = names.reject { |name| described_class::ROUTE_LABEL.key?(name) }

    expect(missing).to be_empty,
                       -> { "这些页面 ROUTE_LABEL 里没有名字，助手在这些页上认不出用户在看什么：\n  #{missing.join("\n  ")}" }
  end
end
