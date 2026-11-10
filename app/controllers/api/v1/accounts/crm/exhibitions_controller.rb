# 展会邀约获客：展会 CRUD + 按国家/地区匹配自己已有客户 + 加入邀约名单。
# 邀请函生成/阶段流转在 Crm::ExhibitionInvitesController。客户在线确认走公开落地页。
class Api::V1::Accounts::Crm::ExhibitionsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_exhibition,
                only: [:show, :update, :destroy, :candidates, :add_invites, :apollo_search, :add_apollo_invites, :generate_sop_drafts]

  def index
    @exhibitions = Current.account.crm_exhibitions.recent
  end

  def show
    @invites = detail_invites
  end

  def create
    @exhibition = Current.account.crm_exhibitions.create!(
      exhibition_params.merge(account_owner_id: current_user.id)
    )
    @invites = []
    render :show
  end

  def update
    @exhibition.update!(exhibition_params)
    @invites = detail_invites
    render :show
  end

  def destroy
    @exhibition.destroy!
    head :no_content
  end

  # 匹配潜客（按国家/地区），从当前用户可见客户里筛，排除已在名单里的。
  def candidates
    @candidates = Crm::ExhibitionMatcher
                  .new(@exhibition, visible_customers)
                  .candidates(include_low: params[:include_low].to_s == 'true')
  end

  # 加入邀约名单：customer_ids[] → 建 pending 邀约（已存在则跳过），按匹配级别定级。
  def add_invites
    ids = Array(params[:customer_ids]).map(&:to_i).uniq
    visible_customers.where(id: ids).find_each do |customer|
      invite = @exhibition.invites.find_or_initialize_by(crm_customer_id: customer.id)
      next unless invite.new_record?

      invite.account = Current.account
      invite.owner_id = current_user.id
      invite.match_level = Crm::ExhibitionMatcher.level_for(@exhibition, customer)
      invite.save!
    end
    @invites = detail_invites
    render :show
  end

  # 从 Apollo 企业库找新买家（突破自有客户池）：按国家 + 行业/产品关键词搜，滤掉 CRM 已有的公司。
  def apollo_search
    client = Crm::ApolloClient.new(account: Current.account, scene: 'exhibition', user: current_user)
    return render(json: { error: '还没配置 Apollo：请到「邮件中心 → AI 设置」填入 Apollo API Key' }, status: :unprocessable_entity) unless client.configured?

    results = client.search_companies(country: params[:country], keywords: params[:keywords])
    existing = Current.account.crm_customers.pluck(:name).compact.to_set { |n| n.downcase.strip }
    @apollo_results = results.reject { |c| existing.include?(c[:name].to_s.downcase.strip) }
    render :apollo_search
  end

  # 选中的 Apollo 公司 → 建 CRM 客户（source=展会）并加入本展会邀约名单。
  def add_apollo_invites
    Array(params[:companies]).each do |c|
      customer = lead_customer_for(c)
      add_invite_for(customer) if customer
    end
    @invites = detail_invites
    render :show
  end

  SOP_LABELS = { 'teaser' => '预告', 'invite' => '邀请函', 'confirm' => '确认', 'reminder' => '行前提醒' }.freeze

  # 4 步 SOP 分步群发：AI 出一份该步模板(含 {{COMPANY}}/{{LINK}} 占位)，对选中邀约逐一合并成
  # 邮件草稿存进「邮件中心」，业务员过目再发（不自动外发）。缺邮箱的客户跳过。
  def generate_sop_drafts # rubocop:disable Metrics/AbcSize
    stage = params[:stage].to_s
    return render(json: { error: '无效步骤' }, status: :unprocessable_entity) unless Crm::EmailAiService::STAGE_TEMPLATE_SYSTEMS.key?(stage)

    ai = Crm::EmailAiService.new(account: Current.account)
    subj_tpl, body_tpl = ai.compose_stage_template(exhibition: @exhibition, stage: stage)
    invites = scope_by_team_owner(@exhibition.invites, column: :owner_id)
              .includes(:customer).where(id: Array(params[:invite_ids]))
    created = 0
    skipped = 0
    invites.find_each do |inv|
      if inv.customer&.contact_email.to_s.strip.blank?
        skipped += 1
      else
        create_sop_draft(inv, subj_tpl, body_tpl)
        created += 1
      end
    end
    render json: { created: created, skipped: skipped, label: SOP_LABELS[stage] }
  rescue Crm::EmailAiService::NotConfigured => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # 把一条邀约按模板合并成一封草稿邮件（{{COMPANY}}=联系人/公司名，{{LINK}}=专属确认链接）。
  def create_sop_draft(invite, subj_tpl, body_tpl) # rubocop:disable Metrics/AbcSize
    company = invite.customer.primary_contact_name.presence || invite.customer.name
    link = invite.public_confirm_url
    merge = ->(t) { t.to_s.gsub('{{COMPANY}}', company).gsub('{{LINK}}', link) }
    body = merge.call(body_tpl)
    Current.account.crm_emails.create!(
      owner_id: current_user.id, folder: 'DRAFT', send_status: 'DRAFT',
      to_address: invite.customer.contact_email.to_s.strip,
      subject: merge.call(subj_tpl.presence || @exhibition.name),
      body: body, body_html: CGI.escapeHTML(body).gsub("\n", '<br>'),
      crm_customer_id: invite.crm_customer_id, email_date: Time.current
    )
  end

  # Apollo 公司 → 找同名 CRM 客户，没有则建一条「展会线索」客户（LEAD）。名称为空跳过。
  def lead_customer_for(company)
    name = company[:name].to_s.strip
    return if name.blank?

    Current.account.crm_customers.where('LOWER(name) = ?', name.downcase).first ||
      Current.account.crm_customers.create!(
        name: name, account_owner_id: current_user.id,
        # 国家用展会所在国码（合法枚举）；Apollo 的行业/域名是自由文本，存备注而非受校验的字段。
        trade_country: @exhibition.country.presence, trade_city: company[:city].presence,
        source_channel: 'EXHIBITION', customer_status: 'PROSPECT',
        customer_remark: ['Apollo 展会线索', company[:industry], company[:domain]].compact_blank.join(' · ')
      )
  end

  # 把客户加入本展会邀约名单（已在则跳过）。
  def add_invite_for(customer)
    invite = @exhibition.invites.find_or_initialize_by(crm_customer_id: customer.id)
    return unless invite.new_record?

    invite.account = Current.account
    invite.owner_id = current_user.id
    invite.match_level = Crm::ExhibitionMatcher.level_for(@exhibition, customer)
    invite.save!
  end

  def check_authorization
    authorize(Crm::Exhibition)
  end

  def fetch_exhibition
    @exhibition = Current.account.crm_exhibitions.find(params[:id])
  end

  # 详情里的邀约名单：按团队口径收口（管理员全部 / 主管本团队 / 业务员本人）。
  def detail_invites
    scope_by_team_owner(@exhibition.invites, column: :owner_id)
      .includes(:customer, :owner)
      .order(created_at: :desc)
  end

  def exhibition_params
    params.require(:exhibition).permit(
      :name, :country, :region, :city, :venue, :hall, :booth_no, :website,
      :starts_on, :ends_on, :featured_products, :theme, :status
    )
  end
end
