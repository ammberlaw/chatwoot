# 文档中心资料板块：index 返回当前用户可见的板块（管理员/文档中心负责人全量），
# create/update/destroy 仅管理员（自定义板块 + 配置各板块可见部门）。
class Api::V1::Accounts::Crm::DocSectionsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization

  # 「销售资料」板块是销售资料知识库的结构容器（其它控制器按名解析），删除/改名会破坏该库，单独保护。
  PROTECTED_NAME = '销售资料'.freeze

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

  # 管理员/副管理员可改名（自定义）+ 配置负责人/可见成员；「销售资料」板块名受保护。
  def update
    @section = Current.account.crm_doc_sections.find(params[:id])
    updates = member_updates.merge(name_update)
    return if performed?

    @section.update!(updates)
    render json: section_json(@section)
  end

  # 管理员/副管理员可删任意板块；板块下文档回落为「未分板块」。「销售资料」板块受保护。
  # 删除的默认板块不再自动重建（ensure_defaults! 仅在账号无任何板块时初始化一次）。
  def destroy
    section = Current.account.crm_doc_sections.find(params[:id])
    return render json: { error: '「销售资料」板块不可删除' }, status: :unprocessable_entity if section.name == PROTECTED_NAME

    section.destroy!
    head :ok
  end

  private

  def member_updates
    updates = {}
    updates[:viewer_ids] = sanitized_member_ids(:viewer_ids) if params[:section].key?(:viewer_ids)
    updates[:manager_ids] = sanitized_member_ids(:manager_ids) if params[:section].key?(:manager_ids)
    updates
  end

  # 改名：「销售资料」板块受保护、名称不可空；校验失败直接渲染错误（调用方以 performed? 判定）。
  def name_update
    return {} unless params[:section].key?(:name)

    if @section.name == PROTECTED_NAME
      render json: { error: '「销售资料」板块不可改名' }, status: :unprocessable_entity
      return {}
    end

    name = params[:section][:name].to_s.strip
    if name.blank?
      render json: { error: '板块名称不能为空' }, status: :unprocessable_entity
      return {}
    end

    { name: name }
  end

  def section_json(section)
    {
      id: section.id, name: section.name,
      viewer_ids: section.viewer_ids,
      viewer_names: User.where(id: section.viewer_ids).pluck(:name),
      manager_ids: section.manager_ids,
      manager_names: User.where(id: section.manager_ids).pluck(:name),
      is_default: Crm::DocSection::DEFAULT_SECTIONS.include?(section.name),
      is_protected: section.name == PROTECTED_NAME
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

  # 文档中心为全员共享模块：板块列表对无 CRM 销售数据权限者（如人事）开放，
  # 供其渲染文档中心；板块的增删改仍需 CRM 权限 + 管理员（DocSectionPolicy）。
  def ensure_crm_access
    return if action_name == 'index'

    super
  end

  def check_authorization
    authorize(Crm::DocSection)
  end
end
