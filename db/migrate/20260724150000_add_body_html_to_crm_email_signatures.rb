class AddBodyHtmlToCrmEmailSignatures < ActiveRecord::Migration[7.1]
  def change
    # 富文本签名：body_html 存带格式的 HTML（字体/颜色/图片等），body 留纯文本兜底（text part / 列表预览）。
    add_column :crm_email_signatures, :body_html, :text
  end
end
