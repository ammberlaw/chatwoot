# 金蝶商品档案导入 MES 物料。
#
#   bundle exec rake 'mes:import_materials[tmp/mes_import/tablet_codes.xlsx,1]'                 # 试运行，不落库
#   bundle exec rake 'mes:import_materials[tmp/mes_import/tablet_codes.xlsx,1,commit]'          # 真写（产线默认 TABLET）
#   bundle exec rake 'mes:import_materials[路径,1,commit,COMMERCIAL_DISPLAY]'                    # 导到其它产线
#
# 表头固定为金蝶导出的 8 列：商品编码/商品名称/商品类别/规格型号/辅助属性管理/描述/计量单位/成本计算方法。
# 「辅助属性管理」列只有一个「是」，没有属性值也没有 SKU 明细——金蝶这个导出口不带那层。
# 标了「是」的记录下来单独报告，等拿到 SKU 明细再补；没标的就是单一物料，直接一条一物料。
MES_IMPORT_HEADERS = %w[商品编码 商品名称 商品类别 规格型号 辅助属性管理 描述 计量单位 成本计算方法].freeze

# 金蝶品类 → 本系统仓别。实际仓库只有 原料仓/在制品仓/成品仓/废料仓，没有辅料仓，
# 所以除成品与裸机外一律进原料仓；细分品类原样存 item_category，不靠 category 承载。
MES_IMPORT_WAREHOUSE = { '成品' => 'FINISHED', '裸机' => 'SEMI' }.freeze
MES_IMPORT_DEFAULT_WAREHOUSE = 'RAW'.freeze

namespace :mes do
  desc '从金蝶商品档案 xlsx 导入 MES 物料（默认试运行，第三个参数传 commit 才写库）'
  task :import_materials, %i[path account_id mode product_line] => :environment do |_t, args|
    path = args[:path].presence or abort('用法: rake "mes:import_materials[文件路径,账号id,commit]"')
    account = Account.find(args[:account_id].presence || 1)
    commit = args[:mode].to_s == 'commit'

    sheet = Roo::Spreadsheet.open(path, extension: :xlsx)
    header = sheet.row(1).map { |v| v.to_s.strip }
    abort("表头对不上，期望：#{MES_IMPORT_HEADERS.join(' / ')}\n实际：#{header.join(' / ')}") if header != MES_IMPORT_HEADERS

    rows = (2..sheet.last_row).map { |i| MES_IMPORT_HEADERS.zip(sheet.row(i)).to_h }
                              .select { |r| r['商品编码'].to_s.strip.present? }

    existing = account.mes_materials.pluck(:material_no).to_set
    stats = Hash.new(0)
    stats_by_wh = Hash.new(0)
    stats_by_cat = Hash.new(0)
    with_aux = []
    failures = []

    ActiveRecord::Base.transaction do
      rows.each do |row|
        no = row['商品编码'].to_s.strip
        with_aux << no if row['辅助属性管理'].to_s.strip.present?

        attrs = {
          material_no: no,
          name: row['商品名称'].to_s.strip,
          item_category: row['商品类别'].to_s.strip.presence,
          category: MES_IMPORT_WAREHOUSE.fetch(row['商品类别'].to_s.strip, MES_IMPORT_DEFAULT_WAREHOUSE),
          specification: row['规格型号'].to_s.strip.presence,
          unit: row['计量单位'].to_s.strip.presence || '个',
          remark: row['描述'].to_s.strip.presence,
          # 产品线存代号不存中文：系统里是 TABLET / COMMERCIAL_DISPLAY，
          # 前端按代号筛选（useMesProductLine），写中文会导致这批物料在产线切换下全部筛不出来。
          product_line: args[:product_line].presence || 'TABLET'
        }

        stats_by_wh[attrs[:category]] += 1
        stats_by_cat[attrs[:item_category] || '(空)'] += 1

        record = account.mes_materials.find_or_initialize_by(material_no: no)
        was_new = record.new_record?
        record.assign_attributes(attrs)

        if record.valid?
          record.save! if commit
          stats[was_new ? :created : :updated] += 1
        else
          stats[:invalid] += 1
          failures << [no, record.errors.full_messages.join('; ')]
        end
      end
      raise ActiveRecord::Rollback unless commit
    end

    puts "\n文件：#{path}"
    puts "账号：#{account.id} #{account.name}　模式：#{commit ? '写库' : '试运行（不落库）'}"
    puts "读到 #{rows.size} 行，其中库里已存在 #{rows.count { |r| existing.include?(r['商品编码'].to_s.strip) }} 条"
    puts "新建 #{stats[:created]}　更新 #{stats[:updated]}　校验不过 #{stats[:invalid]}"
    puts "带辅助属性（需补 SKU 明细）：#{with_aux.size} 条"
    puts "仓别分布：#{stats_by_wh.map { |k, v| "#{k} #{v}" }.join('　')}"
    puts "品类：#{stats_by_cat.size} 类，最多的是 #{stats_by_cat.max_by(3) { |_k, v| v }.map { |k, v| "#{k}(#{v})" }.join('、')}"

    if failures.any?
      puts "\n--- 校验不通过（按原因归类，各列前 3 条） ---"
      failures.group_by { |_no, msg| msg }.each do |msg, list|
        puts "#{list.size} 条：#{msg}"
        list.first(3).each { |pair| puts "    #{pair.first}" }
      end
    end
    puts "\n试运行结束，什么都没写。加第三个参数 commit 才会真的落库。" unless commit
  end
end
