class Api::V1::Accounts::Crm::EmailTemplatesController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_template, only: [:show, :update, :destroy]

  def index
    scope = visible_templates
    scope = scope.company_templates if params[:filter] == 'company'
    scope = scope.personal_of(current_user.id) if params[:filter] == 'mine'
    scope = scope.where(category: params[:category]) if params[:category].present?
    @templates = scope.order(:category, :name)
  end

  def show; end

  def create
    attrs = template_params
    scope = attrs[:scope].presence || 'PERSONAL'
    return render_forbidden if scope == 'COMPANY' && !company_manageable?

    @template = Current.account.crm_email_templates.create!(attrs.merge(owner_id: current_user.id, scope: scope))
    attach_files
  end

  def update
    return render_forbidden unless template_manageable?(@template)

    # 归属范围(scope)建后不改，避免个人↔企业转换带来的归属混乱。
    @template.update!(template_params.except(:scope))
    purge_removed_files
    attach_files
  end

  def destroy
    return render_forbidden unless template_manageable?(@template)

    @template.destroy!
    head :ok
  end

  private

  # 单条也按可见范围收口：企业模版全员可见，个人模版仅归属人；防凭 id 越权访问他人个人模版。
  def fetch_template
    @template = visible_templates.find(params[:id])
  end

  # 可见模板：企业模版 + 自己的个人模版。
  def visible_templates
    base = Current.account.crm_email_templates
    base.company_templates.or(base.personal_of(current_user.id))
  end

  # 企业模版管理权：超管/副管理员/部门负责人（与销售资料公司文档同口径）。
  def company_manageable?
    au = Current.account_user
    au.administrator? || au.crm_deputy_admin? || au.crm_manager?
  end

  # 可管理：个人模版仅归属人；企业模版需管理权。
  def template_manageable?(template)
    return template.owner_id == current_user.id if template.scope == 'PERSONAL'

    company_manageable?
  end

  def render_forbidden
    render json: { error: '无权操作该模板（企业模版仅管理员/主管可改，个人模版仅本人可改）' }, status: :forbidden
  end

  def check_authorization
    authorize(Crm::EmailTemplate)
  end

  def template_params
    params.require(:template).permit(:name, :category, :subject_template, :body, :description, :scope)
  end

  # 新上传的附件追加（不动已有）；multipart 下 template[files][] 传 File。
  def attach_files
    files = params.dig(:template, :files)
    @template.files.attach(files) if files.present?
  end

  # 编辑时前端勾掉的已有附件按 blob/attachment id 移除。
  def purge_removed_files
    ids = Array(params.dig(:template, :remove_file_ids)).map(&:to_s).reject(&:blank?)
    return if ids.empty?

    @template.files.attachments.each { |a| a.purge if ids.include?(a.id.to_s) }
  end
end
