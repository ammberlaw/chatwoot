require 'rails_helper'

RSpec.describe ConversationPolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator_context) { { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }

  let(:conversation) { create(:conversation, account: account) }

  permissions :destroy? do
    context 'when user is an administrator' do
      it 'allows destroy' do
        expect(subject).to permit(administrator_context, conversation)
      end
    end

    context 'when user is an agent' do
      it 'denies destroy' do
        expect(subject).not_to permit(agent_context, conversation)
      end
    end
  end

  permissions :index? do
    context 'when user is authenticated' do
      it 'allows index' do
        expect(subject).to permit(agent_context, conversation)
      end
    end
  end

  permissions :show? do
    context 'when user is an administrator' do
      it 'allows access' do
        expect(subject).to permit(administrator_context, conversation)
      end
    end

    # 2026-09-19 收紧（口径见 Conversations::Visibility）：单条鉴权必须与列表过滤同源，
    # 否则会出现「列表里看不到、直接把会话链接输进地址栏却打得开」。
    context 'when agent is a member of a shared inbox' do
      let(:inbox) { create(:inbox, account: account) }
      let(:conversation) { create(:conversation, account: account, inbox: inbox) }

      before { create(:inbox_member, user: agent, inbox: inbox) }

      it 'denies access when the conversation is not assigned to them' do
        expect(subject).not_to permit(agent_context, conversation)
      end

      it 'allows access once the conversation is assigned to them' do
        conversation.update!(assignee: agent)
        expect(subject).to permit(agent_context, conversation)
      end

      it 'allows access when they were pulled in as a participant' do
        create(:conversation_participant, conversation: conversation, user: agent, account: account)
        expect(subject).to permit(agent_context, conversation)
      end
    end

    # 个人号收件箱＝业务员自己绑的 WhatsApp 号，整箱都该看得见，哪怕某条转给了同事协办。
    context 'when the conversation is in the agent own personal whatsapp inbox' do
      let(:inbox) { create(:inbox, :personal_whatsapp, account: account) }
      let(:conversation) { create(:conversation, account: account, inbox: inbox) }

      before { create(:inbox_member, user: agent, inbox: inbox) }

      it 'allows access even when unassigned' do
        expect(subject).to permit(agent_context, conversation)
      end

      it 'allows access even when assigned to a colleague' do
        conversation.update!(assignee: create(:user, account: account, role: :agent))
        expect(subject).to permit(agent_context, conversation)
      end
    end

    # Chatwoot 原生的 team 放行也一并去掉：本账号从未启用 team，留着就是个将来会
    # 悄悄放开可见性的口子。
    context 'when agent only shares a team with the conversation' do
      let(:team) { create(:team, account: account) }
      let(:conversation) { create(:conversation, :with_team, account: account, team: team) }

      before { create(:team_member, team: team, user: agent) }

      it 'denies access' do
        expect(subject).not_to permit(agent_context, conversation)
      end
    end

    context 'when agent has no relationship to the conversation' do
      let(:conversation) { create(:conversation, account: account) }

      it 'denies access' do
        expect(subject).not_to permit(agent_context, conversation)
      end
    end
  end
end
