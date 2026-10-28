# 知识库文档的正文抽取结果。
#
# 为什么要存下来而不是每次现抽：生产库里 1452 篇知识库文档，正文超 50 字的只有 2 篇——
# 其余全是挂着 PDF 的空壳。AI 答「K705 过了哪些认证」「CE 和 FCC 什么区别」时
# 只能看见文件名、读不出内容。抽一次存起来，之后搜索直接走数据库。
#
# extract_state 必须有，不能只看 extracted_text 是否为空：抽不出来有两种，
# 「还没抽」和「抽过了但这份确实没有文字层」（实测生产 40 份 PDF 里有 1 份是
# 已转曲的画册，文字是矢量路径）。两者混在一起，补录任务会永远重试那一份。
class AddExtractedTextToCrmKnowledgeDocs < ActiveRecord::Migration[7.1]
  def change
    change_table :crm_knowledge_docs, bulk: true do |t|
      t.text :extracted_text
      t.datetime :extracted_at
      # pending=没抽过 / done=抽到正文 / empty=抽过但没文字层 / failed=解析报错 / skipped=类型不支持
      t.string :extract_state
      t.string :extract_error
    end
    add_index :crm_knowledge_docs, [:account_id, :extract_state]
  end
end
