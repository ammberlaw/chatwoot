require 'rails_helper'

# 会话可见性的唯一口径。三处（列表过滤 / 单条鉴权 / 实时推送）共用这里，
# 所以这个 spec 是那条「业务员不该看见同事的客户会话」的总闸。
RSpec.describe Conversations::Visibility do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  # 公司公共号：Cloud API，全体业务员都是成员——问题就出在这
  let(:shared_inbox) { create(:inbox, account: account) }
  # 个人号：业务员自己绑的 WhatsApp，一号一箱只有本人
  let(:personal_inbox) { create(:inbox, :personal_whatsapp, account: account) }

  before do
    create(:inbox_member, user: agent, inbox: shared_inbox)
    create(:inbox_member, user: colleague, inbox: shared_inbox)
    create(:inbox_member, user: agent, inbox: personal_inbox)
  end

  def scope_for(user)
    described_class.scope_for(account.conversations, user, account)
  end

  describe '公共收件箱' do
    it '⚠️ 是收件箱成员不等于看得见整箱——同事的客户会话一条都不给' do
      colleague_conversation = create(:conversation, account: account, inbox: shared_inbox, assignee: colleague)

      expect(scope_for(agent)).not_to include(colleague_conversation)
      expect(described_class).not_to be_visible(colleague_conversation, agent, account)
    end

    it '分到自己头上的看得见' do
      mine = create(:conversation, account: account, inbox: shared_inbox, assignee: agent)

      expect(scope_for(agent)).to include(mine)
      expect(described_class).to be_visible(mine, agent, account)
    end

    it '未分配的不给业务员看（公司号开着自动分配，落到人头上才出现）' do
      unassigned = create(:conversation, account: account, inbox: shared_inbox, assignee: nil)

      expect(scope_for(agent)).not_to include(unassigned)
      expect(described_class).not_to be_visible(unassigned, agent, account)
    end

    it '被同事拉进来协办的那条看得见' do
      conversation = create(:conversation, account: account, inbox: shared_inbox, assignee: colleague)
      create(:conversation_participant, conversation: conversation, user: agent, account: account)

      expect(scope_for(agent)).to include(conversation)
      expect(described_class).to be_visible(conversation, agent, account)
    end
  end

  describe '个人号收件箱' do
    it '整箱都看得见，未分配的也算——那是他自己的号' do
      conversation = create(:conversation, account: account, inbox: personal_inbox, assignee: nil)

      expect(scope_for(agent)).to include(conversation)
      expect(described_class).to be_visible(conversation, agent, account)
    end

    it '某条转给同事协办后，号主自己仍看得见' do
      conversation = create(:conversation, account: account, inbox: personal_inbox, assignee: colleague)

      expect(scope_for(agent)).to include(conversation)
    end

    it '别人的个人号一条都看不到' do
      other_inbox = create(:inbox, :personal_whatsapp, account: account)
      create(:inbox_member, user: colleague, inbox: other_inbox)
      conversation = create(:conversation, account: account, inbox: other_inbox, assignee: colleague)

      expect(scope_for(agent)).not_to include(conversation)
      expect(described_class).not_to be_visible(conversation, agent, account)
    end
  end

  describe '实时推送对象' do
    it '公共号只推给被指派人与参与者，不推给整箱成员' do
      conversation = create(:conversation, account: account, inbox: shared_inbox, assignee: colleague)
      participant = create(:user, account: account, role: :agent)
      create(:inbox_member, user: participant, inbox: shared_inbox) # 参与者必须先是收件箱成员（模型校验）
      create(:conversation_participant, conversation: conversation, user: participant, account: account)

      audience = described_class.audience(conversation)

      expect(audience).to include(colleague, participant)
      expect(audience).not_to include(agent)
    end

    it '公共号未分配的会话谁也不推（管理员由 user_tokens 另行补上）' do
      conversation = create(:conversation, account: account, inbox: shared_inbox, assignee: nil)

      expect(described_class.audience(conversation)).to be_empty
    end

    it '个人号推给号主本人' do
      conversation = create(:conversation, account: account, inbox: personal_inbox, assignee: nil)

      expect(described_class.audience(conversation)).to include(agent)
    end

    # ⚠️ 个人号里把某条转给同事协办：号主和同事都得收到推送。
    # 只推号主的话，接手的同事看得见这条会话却不知道客户回了消息，得手动刷新。
    it '个人号里转给同事的那条，号主与同事都要推' do
      conversation = create(:conversation, account: account, inbox: personal_inbox, assignee: colleague)

      expect(described_class.audience(conversation)).to include(agent, colleague)
    end
  end

  describe '管理员' do
    it '不走这套过滤（调用方短路），这里只确认没把管理员算成可见者之一' do
      conversation = create(:conversation, account: account, inbox: shared_inbox, assignee: colleague)

      # 管理员的全量可见在 PermissionFilterService#perform 里短路，audience 不重复查管理员，
      # 由 ActionCableListener#user_tokens 统一补。
      expect(described_class.audience(conversation)).not_to include(admin)
    end
  end
end
