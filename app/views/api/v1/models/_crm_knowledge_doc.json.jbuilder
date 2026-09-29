json.id resource.id
json.name resource.name
json.category resource.category
json.category_id resource.category_id
json.summary resource.summary
json.scope resource.scope
json.library resource.library
json.section_id resource.section_id
json.body resource.body
json.owner_id resource.owner_id
json.files resource.files.map { |f|
  {
    id: f.id, filename: f.filename.to_s, byte_size: f.byte_size,
    url: url_for(f),
    # 下载：强制 attachment。默认 url_for 对 PDF 发 inline，浏览器只好拿 URL 末段
    # ——对象存储的随机 key——当文件名（邮件附件同样的坑，见 8e234d900）。
    download_url: rails_blob_url(f, disposition: 'attachment'),
    # 预览：同源代理链接，末段是真文件名。redirect 链接会 302 到对象存储，
    # 末段变成随机 key；浏览器若设了「下载 PDF 而不是在浏览器中打开」，
    # iframe 里就只剩一张以 key 命名的占位页，既看不了也存不对名字。
    proxy_url: rails_storage_proxy_url(f)
  }
}
json.updated_at resource.updated_at
