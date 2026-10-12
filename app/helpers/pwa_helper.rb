module PwaHelper
  # iOS 只在 media query 精确匹配某台设备时才显示启动图，否则「添加到主屏」启动会白屏。
  # 每项为 [device_width, device_height, device_pixel_ratio]，竖屏（manifest 已锁 portrait）。
  IOS_SPLASH_DEVICES = [
    [320, 568, 2],  [375, 667, 2],  [414, 736, 3],  [375, 812, 3],
    [414, 896, 2],  [414, 896, 3],  [390, 844, 3],  [428, 926, 3],
    [393, 852, 3],  [430, 932, 3],  [402, 874, 3],  [440, 956, 3],
    [768, 1024, 2], [810, 1080, 2], [820, 1180, 2],
    [834, 1112, 2], [834, 1194, 2], [1024, 1366, 2]
  ].freeze

  # 图标 URL 上的版本号。favicon/apple-icon 这些静态文件带一年的 max-age，
  # 换了图标浏览器照旧拿缓存（Chrome 的 favicon 缓存尤其顽固），得换 URL 才会重取。
  # 按 favicon 内容算，换图自动变——不用记得手工改版本号。
  def brand_icon_version
    @brand_icon_version ||= Digest::MD5.file(Rails.public_path.join('favicon-32x32.png')).hexdigest[0, 8]
  end

  def ios_splash_links
    IOS_SPLASH_DEVICES.map do |width, height, ratio|
      media = "(device-width: #{width}px) and (device-height: #{height}px) " \
              "and (-webkit-device-pixel-ratio: #{ratio}) and (orientation: portrait)"
      { media: media, href: "/pwa/splash/apple-splash-#{width * ratio}x#{height * ratio}.png" }
    end
  end
end
