require 'rails_helper'

RSpec.describe Conversations::PermissionFilterService do
  let(:account) { create(:account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:another_conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:inbox) { create(:inbox, account: account) }

  # This inbox_member is used to establish the agent's access to the inbox
  before { create(:inbox_member, user: agent, inbox: inbox) }

  describe '#perform' do
    context 'when user is an administrator' do
      it 'returns all conversations' do
        result = described_class.new(
          account.conversations,
          admin,
          account
        ).perform

        expect(result).to include(conversation)
        expect(result).to include(another_conversation)
        expect(result.count).to eq(2)
      end
    end

    # 2026-09-19 收紧：共享收件箱里「是成员」不再等于看得见整箱，只看分到自己头上的。
    # 公司 WhatsApp 号十几个成员全是业务员，按原口径每个业务员都看得见全公司的客户会话。
    context 'when user is an agent in a shared inbox' do
      it 'only returns the conversations assigned to them' do
        conversation.update!(assignee: agent)

        result = described_class.new(account.conversations, agent, account).perform

        expect(result).to include(conversation)
        expect(result).not_to include(another_conversation)
      end

      it 'returns nothing when none of them are assigned to the agent' do
        result = described_class.new(account.conversations, agent, account).perform

        expect(result).to be_empty
      end

      it 'returns the conversations they were pulled into as a participant' do
        create(:conversation_participant, conversation: another_conversation, user: agent, account: account)

        result = described_class.new(account.conversations, agent, account).perform

        expect(result).to include(another_conversation)
      end
    end

    # 个人号收件箱：那是业务员自己的 WhatsApp 号，整箱可见。
    context 'when the inbox is the agent own personal whatsapp number' do
      let!(:inbox) { create(:inbox, :personal_whatsapp, account: account) }

      it 'returns every conversation in that inbox regardless of assignee' do
        another_conversation.update!(assignee: create(:user, account: account, role: :agent))

        result = described_class.new(account.conversations, agent, account).perform

        expect(result).to include(conversation)
        expect(result).to include(another_conversation)
      end
    end
  end
end
