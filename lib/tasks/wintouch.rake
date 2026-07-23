namespace :wintouch do
  # 重申品牌配置为 Wintouch，并清 GlobalConfig 缓存。
  # 部署收尾调用，防止 installation_configs 被某些流程重置回 "Chatwoot"（locked 行 ConfigLoader 不会自愈）。
  desc '强制品牌为 Wintouch（部署后自愈，防回退 Chatwoot）'
  task brand: :environment do
    logo = '/brand-assets/logo_thumbnail.svg'
    {
      'INSTALLATION_NAME' => 'Wintouch',
      'BRAND_NAME' => 'Wintouch',
      'LOGO' => logo,
      'LOGO_THUMBNAIL' => logo,
      'LOGO_DARK' => logo
    }.each do |name, value|
      config = InstallationConfig.find_or_initialize_by(name: name)
      next if config.value == value

      config.value = value
      config.save!
    end
    GlobalConfig.clear_cache
    puts '[wintouch:brand] 品牌已重申为 Wintouch'
  end
end
