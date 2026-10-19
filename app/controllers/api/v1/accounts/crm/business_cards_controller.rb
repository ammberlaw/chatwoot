# 展会名片：现场连拍 → 后台识别 → 回头批量校对 → 确认建客户。
#
# 名片只归拍的人自己整理（管理员/副管能看全部）：展会上几个业务员分头跑，
# 各自收各自的名片，混在一起谁都不知道哪张该谁跟。
class Api::V1::Accounts::Crm::BusinessCardsController < Api::V1::Accounts::Crm::BaseController
  before_action :fetch_card, only: [:update, :confirm, :destroy]
  before_action :ensure_mine!, only: [:update, :confirm, :destroy]

  RESULTS_PER_PAGE = 30

  def index
    scope = visible_cards.active
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(event_name: params[:event_name]) if params[:event_name].present?
    @cards_count = scope.count
    # 待整理的排在前面，同状态按新拍的在前——展会回来第一件事就是处理最新那批。
    @cards = scope.includes(:owner, :crm_customer, image_attachment: :blob)
                  .order(Arel.sql("CASE status WHEN 'PENDING' THEN 0 WHEN 'PARSED' THEN 1 ELSE 2 END"))
                  .order(created_at: :desc)
                  .page(params[:page] || 1).per(params[:per_page] || RESULTS_PER_PAGE)
  end

  # 展会名称候选：自己最近用过的那几个，拍下一张时直接点，不用每次重打。
  def events
    names = visible_cards.active.where.not(event_name: [nil, ''])
                         .order(created_at: :desc).limit(200).pluck(:event_name).uniq.first(10)
    render json: { payload: names }
  end

  # 上传一张照片就建一条记录，识别扔后台——现场要的是「拍完就能拍下一张」。
  def create
    return render json: { error: '没有收到照片' }, status: :unprocessable_entity if params[:image].blank?

    @card = Current.account.crm_business_cards.new(
      owner_id: current_user.id, status: 'PENDING', event_name: params[:event_name].presence
    )
    @card.image.attach(params[:image])
    @card.save!
    Crm::BusinessCardParseJob.perform_later(@card.id)
    render 'api/v1/accounts/crm/business_cards/show'
  end

  # 校对：人改了什么就存什么，不碰识别出来的 raw_text（原文要留着对照）。
  def update
    @card.update!(card_params)
    render 'api/v1/accounts/crm/business_cards/show'
  end

  # 确认入库。两条路：建新客户，或者挂到已有客户上（展会上碰到老客户是常事）。
  # 查重是硬门槛：撞上了先回 409 让人看清楚撞的是谁，确认要另建再带 force。
  # 口径与 CustomersController 的建档查重一致（邮箱/电话/WhatsApp/公司名全库查）。
  def confirm
    # 重复点击 / App 断网重试：已经确认过的名片直接回当前状态，不再建一次客户、
    # 也不再往客户备注上追加一遍。这道守卫挡的是明显的重复；真正的并发靠
    # link_to_existing 里的行锁（两个请求可能同时读到 PARSED，在这里都放行）。
    return render 'api/v1/accounts/crm/business_cards/show' if @card.status == 'CONFIRMED'
    return render json: { error: '公司名不能为空，先补上再确认' }, status: :unprocessable_entity unless @card.ready_to_confirm?

    if params[:link_customer_id].present?
      return link_to_existing(params[:link_customer_id])
    end

    hit = duplicate_hit
    return render json: { error: '查到可能重复的客户', duplicate: dup_payload(hit) }, status: :conflict if hit && !truthy?(params[:force])

    customer = Current.account.crm_customers.create!(customer_attributes)
    @card.update!(status: 'CONFIRMED', crm_customer_id: customer.id)
    render 'api/v1/accounts/crm/business_cards/show'
  end

  # 丢弃（不真删）：照片留着，万一后面想起来这张还有用。
  def destroy
    @card.update!(status: 'DISCARDED')
    head :ok
  end

  private

  def fetch_card
    @card = Current.account.crm_business_cards.find(params[:id])
  end

  # 自己的名片自己整理；管理员/副管可以帮忙收拾（展会回来常是助理统一录）。
  def ensure_mine!
    return if @card.owner_id == current_user.id || admin_like?

    render json: { error: '只能整理自己拍的名片' }, status: :forbidden
  end

  def admin_like?
    Current.account_user.administrator? || Current.account_user.crm_deputy_admin?
  end

  def visible_cards
    scope = Current.account.crm_business_cards
    admin_like? ? scope : scope.where(owner_id: current_user.id)
  end

  def card_params
    params.require(:business_card).permit(*Crm::BusinessCard::EDITABLE_FIELDS)
  end

  def truthy?(value) = ActiveModel::Type::Boolean.new.cast(value).present?

  # 建客户：名片字段按 CUSTOMER_FIELD_MAP 搬过去，展会/职位/现场备注并进备注。
  # 归属人是拍的人自己——展会上谁收的名片谁跟。
  def customer_attributes
    attrs = Crm::BusinessCard::CUSTOMER_FIELD_MAP.each_with_object({}) do |(from, to), h|
      value = @card.public_send(from)
      h[to] = value if value.present?
    end
    attrs.merge(account_owner_id: @card.owner_id, source_channel: 'EXHIBITION',
                customer_remark: @card.customer_remark)
  end

  # 挂到已有客户。那张档案可能是别人的私海客户，**联系方式、国家、网址一概不动**——
  # 名片上的未必比档案里的新，覆盖了等于拿旧资料把人家维护好的档案冲掉。
  # 唯一写进去的是这次展会才有的信息（在哪个展会碰到、当场聊了什么），
  # 追加到原备注末尾，原备注一个字不改。
  #
  # 整段放在一个事务里，并对名片和客户都加行锁，解决两件事：
  # ① 并发——两个人同时把各自的名片挂到同一家客户上，读-改-写会让后写的
  #    覆盖先写的，先追加的那条备注就没了；
  # ② 重复——同一张名片被点两次（手抖、App 重试），不能把同一段备注追加两遍。
  # 锁的顺序固定「先名片后客户」，两条路径一致，不会互相死锁。
  def link_to_existing(customer_id)
    Crm::BusinessCard.transaction do
      @card.lock!
      # 拿到行锁后再判一次：并发的两个请求在入口守卫处可能都读到 PARSED，
      # 后拿到锁的那个在这里退出，备注就不会被追加两遍。
      next if @card.status == 'CONFIRMED'

      customer = Current.account.crm_customers.lock.find(customer_id)
      customer.update!(customer_remark: remark_with_card_notes(customer))
      @card.update!(status: 'CONFIRMED', crm_customer_id: customer.id)
    end
    render 'api/v1/accounts/crm/business_cards/show'
  end

  # 原备注 + 本次现场信息，换行隔开。名片上既没填展会名也没写现场备注时
  # 什么都不追加——不能为了"留个痕"往人家备注里塞一行空话。
  def remark_with_card_notes(customer)
    addition = @card.customer_remark
    return customer.customer_remark if addition.blank?

    [customer.customer_remark.presence, addition].compact.join("\n")
  end

  # 全库查重（不按辖区收口）：撞单检测要跨负责人，否则两个业务员各建一份谁都看不见对方那份。
  def duplicate_hit
    all = Current.account.crm_customers
    by_email(all) || by_phone(all, @card.contact_phone) || by_phone(all, @card.whats_app) || by_name(all)
  end

  def by_email(all)
    email = @card.contact_email.to_s.strip.downcase
    return nil if email.length < 5

    all.where('LOWER(TRIM(contact_email)) = ?', email).first
  end

  # 电话归一化与客户页查重同口径（Crm::Customer::PHONE_NORM_SQL）：
  # 只留数字再剥 86/0086 前缀，+86 138-0013-8000 与 13800138000 算同号。
  # 客户的电话和 WhatsApp 各存一列，两列都要比——名片上那个号登记在哪一列并不一定。
  PHONE_COLUMNS = %w[contact_phone whats_app].freeze

  def by_phone(all, value)
    digits = value.to_s.gsub(/\D/, '').sub(/\A(?:00)?86(1\d{10})\z/, '\\1')
    return nil if digits.length < 6

    PHONE_COLUMNS.filter_map do |col|
      all.where("#{format(Crm::Customer::PHONE_NORM_SQL, col)} = :d", d: digits).first
    end.first
  end

  def by_name(all)
    name = @card.company_name.to_s.strip
    return nil if name.length < 2

    all.where('LOWER(TRIM(name)) = ?', name.downcase).first
  end

  # 只报名字、编码、负责人、状态：别人私海客户的联系方式不能借查重结果漏出去。
  def dup_payload(customer)
    {
      id: customer.id, name: customer.name, customer_code: customer.customer_code,
      owner_name: customer.account_owner&.name, customer_status: customer.customer_status
    }
  end
end
