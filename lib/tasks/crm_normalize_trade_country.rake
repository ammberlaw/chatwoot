# 归一化 CRM 客户 trade_country：把小满迁入的「中文国家名」改成英文代码
# （与前端 dashboard/routes/dashboard/crm/constants/countries.js 的 COUNTRY_LABELS 一致）。
#
# 背景：小满迁入的客户把中文国家名（如「新加坡」「中国」）塞进了 trade_country，
# 而模型校验 COUNTRIES 是英文代码（SINGAPORE/CHINA…），导致这些客户「整体编辑」时
# 报 422（Trade country is not included in the list）。本任务把中文归一成代码。
#
# 幂等：只改「中文名」值；已是英文代码的跳过。用 update_all 跳过全量校验，
# 历史脏数据（如非法 trade_country）不阻塞这一窄字段的写入。
#
# 用法：bundle exec rails crm:normalize_trade_country
namespace :crm do
  desc 'Normalize crm_customers.trade_country Chinese names to English codes (idempotent)'
  task normalize_trade_country: :environment do
    zh_to_code = {
      '美国' => 'USA', '德国' => 'GERMANY', '英国' => 'UK', '法国' => 'FRANCE',
      '意大利' => 'ITALY', '西班牙' => 'SPAIN', '加拿大' => 'CANADA', '澳大利亚' => 'AUSTRALIA',
      '中国' => 'CHINA', '日本' => 'JAPAN', '韩国' => 'SOUTH_KOREA', '印度' => 'INDIA',
      '俄罗斯' => 'RUSSIA', '巴西' => 'BRAZIL', '墨西哥' => 'MEXICO', '荷兰' => 'NETHERLANDS',
      '比利时' => 'BELGIUM', '瑞士' => 'SWITZERLAND', '瑞典' => 'SWEDEN', '挪威' => 'NORWAY',
      '丹麦' => 'DENMARK', '芬兰' => 'FINLAND', '奥地利' => 'AUSTRIA', '波兰' => 'POLAND',
      '捷克' => 'CZECH', '土耳其' => 'TURKEY', '阿联酋' => 'UAE', '沙特阿拉伯' => 'SAUDI_ARABIA',
      '新加坡' => 'SINGAPORE', '马来西亚' => 'MALAYSIA', '泰国' => 'THAILAND', '越南' => 'VIETNAM',
      '印度尼西亚' => 'INDONESIA', '菲律宾' => 'PHILIPPINES', '南非' => 'SOUTH_AFRICA',
      '阿根廷' => 'ARGENTINA', '智利' => 'CHILE', '哥伦比亚' => 'COLOMBIA', '秘鲁' => 'PERU',
      '以色列' => 'ISRAEL', '埃及' => 'EGYPT', '尼日利亚' => 'NIGERIA', '肯尼亚' => 'KENYA',
      '希腊' => 'GREECE', '葡萄牙' => 'PORTUGAL', '爱尔兰' => 'IRELAND', '新西兰' => 'NEW_ZEALAND',
      '台湾' => 'TAIWAN', '香港' => 'HONG_KONG', '巴基斯坦' => 'PAKISTAN', '孟加拉国' => 'BANGLADESH',
      '乌克兰' => 'UKRAINE', '罗马尼亚' => 'ROMANIA', '匈牙利' => 'HUNGARY', '保加利亚' => 'BULGARIA',
      '克罗地亚' => 'CROATIA', '摩洛哥' => 'MOROCCO', '伊朗' => 'IRAN', '伊拉克' => 'IRAQ',
      '卡塔尔' => 'QATAR', '科威特' => 'KUWAIT', '阿曼' => 'OMAN', '缅甸' => 'MYANMAR',
      '柬埔寨' => 'CAMBODIA', '老挝' => 'LAOS', '哈萨克斯坦' => 'KAZAKHSTAN', '乌兹别克斯坦' => 'UZBEKISTAN',
      '加纳' => 'GHANA', '塞内加尔' => 'SENEGAL', '安哥拉' => 'ANGOLA', '赞比亚' => 'ZAMBIA',
      '埃塞俄比亚' => 'ETHIOPIA', '喀麦隆' => 'CAMEROON', '坦桑尼亚' => 'TANZANIA', '贝宁' => 'BENIN',
      '索马里' => 'SOMALIA', '多哥' => 'TOGO', '布基纳法索' => 'BURKINA_FASO', '利比亚' => 'LIBYA',
      '博茨瓦纳' => 'BOTSWANA', '津巴布韦' => 'ZIMBABWE', '南苏丹' => 'SOUTH_SUDAN', '马里' => 'MALI',
      '塞拉利昂' => 'SIERRA_LEONE', '几内亚' => 'GUINEA', '佛得角' => 'CAPE_VERDE',
      '中非' => 'CENTRAL_AFRICAN_REPUBLIC', '苏丹' => 'SUDAN', '莫桑比克' => 'MOZAMBIQUE',
      '马拉维' => 'MALAWI', '毛里求斯' => 'MAURITIUS', '阿尔及利亚' => 'ALGERIA', '突尼斯' => 'TUNISIA',
      '科特迪瓦' => 'IVORY_COAST', '乌干达' => 'UGANDA', '卢旺达' => 'RWANDA', '加蓬' => 'GABON',
      '刚果（布）' => 'CONGO', '刚果（金）' => 'DR_CONGO', '马达加斯加' => 'MADAGASCAR',
      '纳米比亚' => 'NAMIBIA', '留尼汪' => 'REUNION', '委内瑞拉' => 'VENEZUELA', '哥斯达黎加' => 'COSTA_RICA',
      '危地马拉' => 'GUATEMALA', '海地' => 'HAITI', '洪都拉斯' => 'HONDURAS', '萨尔瓦多' => 'EL_SALVADOR',
      '玻利维亚' => 'BOLIVIA', '巴巴多斯' => 'BARBADOS', '巴哈马' => 'BAHAMAS', '厄瓜多尔' => 'ECUADOR',
      '乌拉圭' => 'URUGUAY', '巴拉圭' => 'PARAGUAY', '多米尼加' => 'DOMINICAN_REPUBLIC', '巴拿马' => 'PANAMA',
      '牙买加' => 'JAMAICA', '特立尼达和多巴哥' => 'TRINIDAD_AND_TOBAGO', '古巴' => 'CUBA',
      '尼加拉瓜' => 'NICARAGUA', '黎巴嫩' => 'LEBANON', '约旦' => 'JORDAN', '巴林' => 'BAHRAIN',
      '也门' => 'YEMEN', '叙利亚' => 'SYRIA', '阿富汗' => 'AFGHANISTAN', '斯里兰卡' => 'SRI_LANKA',
      '尼泊尔' => 'NEPAL', '蒙古' => 'MONGOLIA', '文莱' => 'BRUNEI', '马尔代夫' => 'MALDIVES',
      '格鲁吉亚' => 'GEORGIA', '亚美尼亚' => 'ARMENIA', '阿塞拜疆' => 'AZERBAIJAN', '塞浦路斯' => 'CYPRUS',
      '马耳他' => 'MALTA', '卢森堡' => 'LUXEMBOURG', '冰岛' => 'ICELAND', '爱沙尼亚' => 'ESTONIA',
      '拉脱维亚' => 'LATVIA', '立陶宛' => 'LITHUANIA', '斯洛伐克' => 'SLOVAKIA', '斯洛文尼亚' => 'SLOVENIA',
      '塞尔维亚' => 'SERBIA', '波黑' => 'BOSNIA', '阿尔巴尼亚' => 'ALBANIA', '北马其顿' => 'NORTH_MACEDONIA',
      '白俄罗斯' => 'BELARUS', '瓦努阿图' => 'VANUATU', '斐济' => 'FIJI',
      '巴布亚新几内亚' => 'PAPUA_NEW_GUINEA', '其他' => 'OTHER'
    }.freeze

    codes = Crm::Customer::COUNTRIES
    mapped = {}
    zh_to_code.each do |zh, code|
      n = Crm::Customer.where(trade_country: zh).update_all(trade_country: code)
      mapped[zh] = n if n.positive?
    end

    total = mapped.values.sum
    puts "归一 #{total} 条 trade_country："
    mapped.each { |zh, n| puts "  #{zh} → #{zh_to_code[zh]}: #{n} 条" }
    puts '  （无中文值可归一）' if mapped.empty?

    remaining = Crm::Customer.where.not(trade_country: nil)
                             .distinct.pluck(:trade_country)
                             .reject { |v| codes.include?(v) }
    if remaining.any?
      puts "⚠️ 仍有未映射的非法 trade_country（需人工核对/补映射）：#{remaining.inspect}"
    else
      puts '✅ 全库 trade_country 已全部合法'
    end
  end
end
