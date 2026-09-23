require 'rails_helper'

# 入站媒体（客户发来的图片/视频/语音/文件）。
# 这条链路以前整个不存在：桥 `if (!text) return` 丢掉、服务 `return if text.blank?` 再丢一次，
# 业务员只能去手机上翻。三种情形都要盖到，尤其「纯媒体」——它没有文字，最容易被判空丢弃。
RSpec.describe Whatsapp::IncomingMessageWhatsappWebService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, :personal_whatsapp, account: account) }

  def blob_for(filename, content_type, bytes = 'fake-binary-content')
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(bytes), filename: filename, content_type: content_type
    )
  end

  def deliver(extra = {})
    described_class.new(
      inbox: inbox,
      params: { source_id: '8613800000000@s.whatsapp.net', phone: '8613800000000',
                name: '客户A', message_id: "M#{SecureRandom.hex(4)}", timestamp: Time.current.to_i }.merge(extra)
    ).perform
    inbox.messages.order(:id).last
  end

  it 'keeps a media-only message instead of dropping it' do
    message = deliver(text: nil, media_signed_id: blob_for('photo.jpg', 'image/jpeg').signed_id)

    expect(message).to be_present
    expect(message.attachments.count).to eq(1)
    expect(message.attachments.first.file_type).to eq('image')
    expect(message.attachments.first.file).to be_attached
  end

  it 'keeps both the caption and the image when a photo carries text' do
    message = deliver(text: '这是样品图', media_signed_id: blob_for('photo.jpg', 'image/jpeg').signed_id)

    expect(message.content).to eq('这是样品图')
    expect(message.attachments.count).to eq(1)
  end

  it 'classifies video, audio and documents by content type' do
    expect(deliver(text: nil, media_signed_id: blob_for('clip.mp4', 'video/mp4').signed_id)
             .attachments.first.file_type).to eq('video')
    expect(deliver(text: nil, media_signed_id: blob_for('voice.ogg', 'audio/ogg').signed_id)
             .attachments.first.file_type).to eq('audio')
    expect(deliver(text: nil, media_signed_id: blob_for('spec.pdf', 'application/pdf').signed_id)
             .attachments.first.file_type).to eq('file')
  end

  # blob 过期/被清理时宁可只留文字，也不要整条消息报错丢掉。
  it 'still stores the text when the staged blob is gone' do
    message = deliver(text: '图发不出来', media_signed_id: 'no-such-signed-id')

    expect(message.content).to eq('图发不出来')
    expect(message.attachments.count).to eq(0)
  end

  it 'drops a message that has neither text nor media' do
    expect { deliver(text: nil) }.not_to change(Message, :count)
  end

  it 'does not create a duplicate when WhatsApp redelivers the same message' do
    id = "M#{SecureRandom.hex(4)}"
    2.times { deliver(text: '重复投递', message_id: id) }

    expect(inbox.messages.where(source_id: id).count).to eq(1)
  end
end
