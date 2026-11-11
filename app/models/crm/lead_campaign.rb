# 一次主动拓客任务：目标市场 + AI 生成的理想客户画像和本地化关键词。
# == Schema Information
#
# Table name: crm_lead_campaigns
#
#  id                     :bigint           not null, primary key
#  auto_run               :boolean          default(FALSE), not null
#  auto_run_at            :datetime
#  dead_keywords          :jsonb
#  default_customer_group :string
#  evidence               :jsonb            not null
#  keywords               :jsonb            not null
#  last_error             :text
#  name                   :string           not null
#  product_hint           :string
#  profile                :jsonb            not null
#  profiled_at            :datetime
#  run_model              :string
#  screen_criteria        :text
#  search_cursor          :jsonb            not null
#  searched_at            :datetime
#  seed_keywords          :string
#  shared                 :boolean          default(TRUE), not null
#  status                 :string           default("DRAFT"), not null
#  target_count           :integer          default(60), not null
#  target_markets         :jsonb            not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  created_by_id          :bigint
#  owner_id               :bigint
#
# Indexes
#
#  index_crm_lead_campaigns_on_account_id_and_status  (account_id,status)
#  index_crm_lead_campaigns_on_created_by_id          (created_by_id)
#  index_crm_lead_campaigns_on_owner_id               (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#
class Crm::LeadCampaign < ApplicationRecord
  self.table_name = 'crm_lead_campaigns'

  # DRAFT 刚建/画像没跑出来 → PROFILED 画像好了 → QUEUED 排队 → SEARCHING 搜索中
  # → DONE 搜完了。失败回到 PROFILED 并写 last_error，人能重跑。
  STATUSES = %w[DRAFT PROFILED QUEUED SEARCHING DONE].freeze
  SEARCH_STALE_AFTER = 15.minutes

  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  attr_readonly :created_by_id
  has_many :leads, class_name: 'Crm::Lead', foreign_key: :crm_lead_campaign_id,
                   dependent: :destroy, inverse_of: :campaign

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def search_run = evidence['search_run'] || {}
  def search_active? = %w[QUEUED SEARCHING].include?(status)

  # 队列预留和执行共用同一把锁；会话结束（包括 worker 退出）时 PostgreSQL 自动释放。
  # 不用有过期时间的 Redis 锁，避免慢任务过期后被第二个 worker 同时执行。
  def with_search_lock
    self.class.connection_pool.with_connection do |connection|
      key = "hashtextextended(#{connection.quote("crm:lead_search:#{id}")}, 0)"
      acquired = connection.select_value("SELECT pg_try_advisory_lock(#{key})")
      next false unless acquired

      begin
        yield
        true
      ensure
        connection.execute("SELECT pg_advisory_unlock(#{key})")
      end
    end
  end

  def enqueue_search!
    job = Crm::LeadSearchJob.new(id)
    reserved = false
    with_search_lock { reserved = reserve_search!(job.job_id) }
    return false unless reserved

    # 手动入口和自动调度均不包外层事务；预留提交后再入队，worker 才能读到状态。
    job.enqueue
    raise ActiveJob::EnqueueError, '搜索排队失败，请稍后重试' unless job.successfully_enqueued?

    true
  rescue StandardError
    with_search_lock { finish_search!(job.job_id, error: '搜索排队失败，请稍后重试') } if reserved
    raise unless reserved

    raise ActiveJob::EnqueueError, '搜索排队失败，请稍后重试'
  end

  def claim_search!(job_id)
    with_lock do
      run = search_run
      next false if run['job_id'].present? && run['job_id'] != job_id
      next false if run['job_id'] == job_id && %w[completed failed].include?(run['state'])

      # 没有 job_id 的是部署前已在队列里的任务；只允许在没有新预留时接管。
      now = Time.current
      update!(status: 'SEARCHING', last_error: nil,
              evidence: evidence.merge('search_run' => run.merge(
                'job_id' => job_id, 'state' => 'running', 'stage' => 'learning_keywords',
                'started_at' => run['started_at'] || now.iso8601(6), 'retry_after' => (now + SEARCH_STALE_AFTER).iso8601(6)
              )))
      true
    end
  end

  def update_search_stage!(stage)
    with_lock { update!(evidence: evidence.merge('search_run' => search_run.merge('stage' => stage))) }
  end

  def search_stale?
    retry_at = search_run['retry_after']
    (retry_at ? Time.iso8601(retry_at) : updated_at + SEARCH_STALE_AFTER) <= Time.current
  end

  def finish_search!(job_id, error: nil)
    with_lock do
      next unless search_run['job_id'] == job_id

      now = Time.current
      state = error ? 'failed' : 'completed'
      run = search_run.merge(search_result_counts(now)).merge(
        'state' => state, 'stage' => state, 'finished_at' => now.iso8601(6), 'error' => error
      )
      attrs = { status: error ? 'PROFILED' : 'DONE', last_error: error, evidence: evidence.merge('search_run' => run) }
      attrs[:searched_at] = now unless error
      update!(attrs)
      run
    end
  end

  # 画像里哪几条是模型推的（没有成交数据撑着）。发开发信之前这几条要人核实。
  def inferred_fields = Array(evidence['inferred'])

  def keywords_for(market)
    Array(keywords).select { |k| k['market'].to_s.casecmp?(market.to_s) }
  end

  private

  def reserve_search!(job_id)
    with_lock do
      next false if (search_active? && !search_stale?) || keywords.blank?

      now = Time.current
      run = { 'job_id' => job_id, 'state' => 'queued', 'stage' => 'queued', 'queued_at' => now.iso8601(6),
              'retry_after' => (now + SEARCH_STALE_AFTER).iso8601(6) }
      update!(status: 'QUEUED', last_error: nil, evidence: evidence.merge('search_run' => run))
      true
    end
  end

  def search_result_counts(finished_at)
    return { 'created_leads' => 0, 'created_companies' => 0 } unless search_run['started_at']

    rows = leads.where(created_at: Time.iso8601(search_run['started_at'])..finished_at).pluck(:domain, :company_name)
    companies = rows.map { |domain, name| domain.presence || name }.uniq
    { 'created_leads' => rows.size, 'created_companies' => companies.size }
  end
end
