require 'rails_helper'

describe Conversations::AssignmentService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  describe '#perform' do
    context 'when assignee_id is blank' do
      before do
        conversation.update!(assignee: agent, assignee_agent_bot: agent_bot)
      end

      it 'clears both human and bot assignees' do
        described_class.new(conversation: conversation, assignee_id: nil).perform

        conversation.reload
        expect(conversation.assignee_id).to be_nil
        expect(conversation.assignee_agent_bot_id).to be_nil
      end
    end

    context 'when assigning a user' do
      before do
        conversation.update!(assignee_agent_bot: agent_bot, assignee: nil)
      end

      it 'sets the agent and clears agent bot' do
        result = described_class.new(conversation: conversation, assignee_id: agent.id).perform

        conversation.reload
        expect(result).to eq(agent)
        expect(conversation.assignee_id).to eq(agent.id)
        expect(conversation.assignee_agent_bot_id).to be_nil
      end
    end

    # 分配会话时接管无主客户：业务员看的「我的客户」按 account_owner_id 筛，
    # 派了活不改归属，他在那个视图里就是找不到人。
    context 'when the contact has a CRM customer' do
      let(:other_agent) { create(:user, account: account) }
      let(:customer) { create(:crm_customer, account: account) }

      before { conversation.contact.update!(crm_customer_id: customer.id) }

      it 'claims the customer when it has no owner' do
        described_class.new(conversation: conversation, assignee_id: agent.id).perform

        expect(customer.reload.account_owner_id).to eq(agent.id)
      end

      it 'leaves a customer owned by someone else untouched' do
        customer.update!(account_owner_id: other_agent.id)

        described_class.new(conversation: conversation, assignee_id: agent.id).perform

        expect(customer.reload.account_owner_id).to eq(other_agent.id)
      end

      it 'does not claim a customer sitting in the public pool' do
        customer.update!(is_in_public_pool: true, public_pool_at: Time.current)

        described_class.new(conversation: conversation, assignee_id: agent.id).perform

        expect(customer.reload.account_owner_id).to be_nil
      end
    end

    context 'when the contact has no CRM customer' do
      it 'assigns the agent without raising' do
        expect do
          described_class.new(conversation: conversation, assignee_id: agent.id).perform
        end.not_to raise_error

        expect(conversation.reload.assignee_id).to eq(agent.id)
      end
    end

    context 'when assigning an agent bot' do
      let(:service) do
        described_class.new(
          conversation: conversation,
          assignee_id: agent_bot.id,
          assignee_type: 'AgentBot'
        )
      end

      it 'sets the agent bot and clears human assignee' do
        conversation.update!(assignee: agent, assignee_agent_bot: nil)

        result = service.perform

        conversation.reload
        expect(result).to eq(agent_bot)
        expect(conversation.assignee_agent_bot_id).to eq(agent_bot.id)
        expect(conversation.assignee_id).to be_nil
      end
    end
  end
end
