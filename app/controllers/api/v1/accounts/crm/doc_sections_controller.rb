# 文档中心资料板块：index 返回当前用户可见的板块（管理员/文档中心负责人全量），
# create/update/destroy 仅管理员（自定义板块 + 配置各板块可见部门）。
class Api::V1::Accounts::Crm::DocSectionsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization

  def index
    Crm::DocSection.ensure_defaults!(Current.account)
    all = Current.account.crm_doc_sections.order(:position, :id)
    @sections = if manage_all?
                  all
                else
                  visible = Crm::DocSection.visible_ids_for(Current.account, current_user.id)
                  managed = Crm::DocSection.managed_ids_for(Current.account, current_user.id)
                  all.where(id: (visible + managed).uniq)
                end
  end

  # 管理员自定义新增板块（排在默认板块之后）。
  def create
    name = params.dig(:section, :name).to_s.strip
    return render json: { error: '板块名称不能为空' }, status: :unprocessable_entity if name.blank?

    position = (Current.account.crm_doc_sections.maximum(:position) || 0) + 1
    @section = Current.account.crm_doc_sections.create!(name: name, position: position)
    render json: section_json(@section)
  end

  def update
    @section = Current.account.crm_doc_sections.find(params[:id])
    updates = {}
    updates[:viewer_ids] = sanitized_member_ids(:viewer_ids) if params[:section].key?(:viewer_ids)
    updates[:manager_ids] = sanitized_member_ids(:manager_ids) if params[:section].key?(:manager_ids)
    @section.update!(updates)
    render json: section_json(@section)
  end

  # 默认板块随 index 自动重建，只允许删自定义板块；板块下文档回落为「未分板块」。
  def destroy
    section = Current.account.crm_doc_sections.find(params[:id])
    return render json: { error: '默认板块不可删除' }, status: :unprocessable_entity if Crm::DocSection::DEFAULT_SECTIONS.include?(section.name)

    section.destroy!
    head :ok
  end

  private

  def section_json(section)
    {
      id: section.id, name: section.name,
      viewer_ids: section.viewer_ids,
      viewer_names: User.where(id: section.viewer_ids).pluck(:name),
      manager_ids: section.manager_ids,
      manager_names: User.where(id: section.manager_ids).pluck(:name),
      is_default: Crm::DocSection::DEFAULT_SECTIONS.include?(section.name)
    }
  end

  # 成员名单（可见成员/负责人）仅接受本账号成员的 user_id。
  def sanitized_member_ids(key)
    ids = Array(params.dig(:section, key)).map(&:to_i).uniq
    Current.account.account_users.where(user_id: ids).pluck(:user_id)
  end

  def manage_all?
    Current.account_user.administrator? || Current.account_user.crm_deputy_admin?
  end

  def check_authorization
    authorize(Crm::DocSection)
  end
end
