# 腾讯云 COS 对「文件名里有连续空格」的上传会算错签名，直接报 SignatureDoesNotMatch。
# 根因是 AWS SDK 与 COS 对请求头里连续空白的规范化规则不一致，而 ActiveStorage 会把文件名
# 放进 Content-Disposition 头、该头参与签名计算。
#
# 后果不是报错给用户看，而是附件静默丢失：生产上客户发来的
# 「SS26090508  深圳盐田入仓单裕泰仓.docx」（两个空格）就是这么没的，界面上看就是一封没附件的邮件。
# 实测同样的内容换成单空格立刻上传成功，与中文、大小都无关。
#
# 在文件名清洗阶段把连续空白压成一个，所有上传路径（邮件附件 / PI / 文档 / 头像）一并生效。
module ActiveStorageFilenameCosSafe
  def sanitized
    super.gsub(/\s+/, ' ').strip
  end
end

Rails.application.config.after_initialize do
  ActiveStorage::Filename.prepend(ActiveStorageFilenameCosSafe)
end
