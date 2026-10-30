# AI 助手记住的事：看一眼、删掉不要的。
#
# 为什么非有个界面不可：记忆只能靠对话里说「忘掉…」来删，而没人知道这回事。
# 生产上余珊珊那两条就是证据——「以后叫我懒宝宝」和「不要叫懒宝宝，叫蓝宝宝」
# 同时存着，助手每轮都带着两条打架的指令，她自己也看不到、删不掉。
class Api::V1::Accounts::Crm::AgentMemoriesController < Api::V1::Accounts::Crm::BaseController
  # 和 AI 助手同一道门：车间、财务这些没有 CRM 角色的人也在 AI 名单里。
  skip_before_action :ensure_crm_access
  before_action :ensure_allowed!

  def index
    @company = Crm::AgentMemory.for_account(Current.account.id).limit(Crm::AgentMemory::MAX_PER_ACCOUNT)
    @mine = Crm::AgentMemory.for_user(Current.account.id, current_user.id).limit(Crm::AgentMemory::MAX_PER_USER)
    @may_edit_company = may_edit_company?
  end

  # 公司规矩只有管理员能删；自己的那档人人删得了自己的。
  def destroy
    row = Current.account.crm_agent_memories.find(params[:id])
    return render json: { error: '公司规矩要管理员才能删' }, status: :forbidden if row.account_wide? && !may_edit_company?
    return render json: { error: '这条不是你的记忆' }, status: :forbidden if !row.account_wide? && row.user_id != current_user.id

    row.destroy!
    head :ok
  end

  private

  def may_edit_company?
    au = Current.account_user
    au.administrator? || au.crm_deputy_admin? || au.crm_manager?
  end

  def ensure_allowed!
    return if Crm::AiSetting.agent_allowed?(Current.account, Current.account_user)

    render json: { error: 'AI 助手还没开放给你' }, status: :forbidden
  end
end
