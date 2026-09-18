# 定制报价的参数模板配置：每条产品线一套字段。仅管理员/副管可改。
class Api::V1::Accounts::Crm::QuoteRequestTemplatesController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :require_admin, except: [:index]
  before_action :fetch_template, only: [:update, :destroy]

  def index
    render json: { payload: Current.account.crm_quote_request_templates.ordered.map { |t| row(t) } }
  end

  def create
    tpl = Current.account.crm_quote_request_templates.new(template_params)
    tpl.creator_id = current_user.id
    tpl.save!
    render json: row(tpl)
  end

  def update
    @template.update!(template_params)
    render json: row(@template)
  end

  def destroy
    # 已有申请引用的模板不让删（dependent: :restrict_with_error），停用即可。
    return render json: { error: '该模板已有申请单，停用即可，不能删除' }, status: :unprocessable_entity unless @template.destroy

    head :ok
  end

  private

  # 控制器名推不出模型（模型在 Crm:: 命名空间下），显式指定，与其它 CRM 控制器同款。
  def check_authorization
    authorize(Crm::QuoteRequestTemplate)
  end

  def fetch_template
    @template = Current.account.crm_quote_request_templates.find(params[:id])
  end

  def require_admin
    au = Current.account_user
    head :forbidden unless au.administrator? || au.crm_deputy_admin?
  end

  def row(t)
    { id: t.id, product_line: t.product_line, name: t.name, description: t.description,
      form_fields: t.form_fields, active: t.active, position: t.position }
  end

  def template_params
    params.require(:template).permit(:product_line, :name, :description, :active, :position,
                                     form_fields: [:key, :label, :type, :required, { options: [] }])
  end
end
