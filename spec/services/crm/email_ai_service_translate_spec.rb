require 'rails_helper'

# 长邮件翻译「牛头不对马嘴」的两个成因：
# ① 后续片段沿用了「第一行给主题译文」的提示词，模型给每段都编一个主题混进正文；
# ② 单行超长时按固定字数硬切，把句子从中间劈开，切口两边都译不对。
# 生产上 39% 的邮件正文超过一段的长度，所以这两条都是常态触发。
describe Crm::EmailAiService do
  subject(:service) { described_class.new(account: create(:account)) }

  describe '切段' do
    it '超长单行在句末断开，不从句子中间切' do
      sentence = "#{'a' * 300}. "
      chunks = service.send(:split_for_translation, sentence * 40).first
      expect(chunks.size).to be > 1
      expect(chunks[0..-2]).to all(match(/\.\s*\z/))
    end

    it '找不到句末时退而在空白处断开' do
      chunks = service.send(:split_for_translation, 'word ' * 2000).first
      expect(chunks.size).to be > 1
      expect(chunks[0..-2]).to all(match(/\s\z/))
    end

    it '短邮件只有一段' do
      expect(service.send(:split_for_translation, "Hello\nWorld").first.size).to eq 1
    end
  end

  describe '主题行' do
    it '从译文里剥出主题和正文' do
      expect(service.send(:split_subject, "SUBJECT: 报价确认\n\n您好：\n附件是报价。"))
        .to eq ['报价确认', "您好：\n附件是报价。"]
    end

    it '没有主题行时原样返回正文' do
      expect(service.send(:split_subject, '您好：附件是报价。')).to eq [nil, '您好：附件是报价。']
    end
  end
end
