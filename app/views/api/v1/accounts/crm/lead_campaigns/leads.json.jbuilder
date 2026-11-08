# 手上压着多少条没处理完的（上限 Crm::Lead::HOLD_LIMIT），前端据此提示。
json.held_count @held_count
json.hold_limit Crm::Lead::HOLD_LIMIT
json.hold_days Crm::Lead::HOLD_DAYS

json.payload do
  json.array! @leads do |lead|
    json.id lead.id
    json.status lead.status
    json.company_name lead.company_name
    json.domain lead.domain
    json.industry lead.industry
    json.country lead.country
    json.city lead.city
    json.person_name lead.person_name
    json.title lead.title
    json.email lead.email
    json.email_status lead.email_status
    json.linkedin_url lead.linkedin_url
    # 搜索阶段只知道「有没有邮箱」，解锁后才有真地址。
    json.email_available lead.email_available?
    # 已经是自家客户的直接标出来——搜出一堆自家客户是这类工具最常见的浪费，
    # 更糟的是业务员不知道，照着发开发信撞到同事头上。所以连**归属人**一起给。
    dup = @dupes[lead.domain.to_s.downcase.delete_prefix('www.')]
    json.dup_customer_id dup&.customer_id || lead.dup_customer_id
    json.dup_customer_name dup&.customer_name
    json.dup_owner_name dup&.owner_name
    # 共享池：这条在谁手上。mine=我领的，空=还在池子里谁都能领。
    json.mine lead.holder_id == current_user.id
    json.claimed_at lead.claimed_at
    # 经理/副管才看得到：这条在谁手上（业务员压根看不见别人的线索）。
    json.holder_name @holders[lead.holder_id]
    json.crm_customer_id lead.crm_customer_id
    json.matched_keyword lead.raw['matched_keyword']
    # 企业库里实际命中的标签。和搜索词不一样说明这个词原样搜不到、退了一步，
    # 差别往往就是「不精准」的来源，所以摆到行上。
    json.apollo_tag lead.raw['apollo_tag']
    # 市场代码（GERMANY/USA…）：前端拿它显示中文国名，和任务头部的写法保持一致。
    json.market lead.raw['market']
    # AI 初筛：yes 像买家 / no 不是（媒体、招聘这类被关键词模糊匹配带出来的）/ unsure 看不出。
    # 只打标不自动删——AI 也会看走眼。
    json.screen lead.raw['screen']
    json.screen_why lead.raw['screen_why']
    # 匹配度 0-100。列表按它排——条数由业务员翻页决定，不由提示词措辞决定。
    json.screen_score lead.raw['screen_score']
    # 一键背调的结果（抓官网 + Apollo）。存下来是因为一次十几秒，不该每次进页面重跑。
    json.bg lead.raw['bg']
    # 背调排队中（异步）。刷新页面后按钮仍显示「背调中…」。
    json.bg_running lead.raw['bg'].blank? && lead.raw['bg_running_at'].present?
    # 搜索阶段白给的公司资料（电话/领英/营收/门店数/上市）——不花 credits，
    # 但业务员判断时最想先看到的就是这些。
    json.org lead.raw['org']
    # 点得开的官网地址。**不能让前端自己拼**——Apollo 存的是 http://www.xxx，
    # 直接当链接会被浏览器的 HTTPS 优先全部拦掉（见 Crm::SiteUrl）。
    json.site_url Crm::SiteUrl.for(domain: lead.domain, website: lead.raw.dig('org', 'website'),
                                   bg_url: lead.raw.dig('bg', 'url'))
    # 行业代码认定「不可能是买家」的（出版/广电/人力这些），列表里默认折叠。
    # 判定放后端，免得黑名单在前后端各写一份走偏。
    json.not_buyer Crm::NaicsLabel.not_buyer?(lead.industry)
    # 丢弃原因码：界面上回显，也是初筛学习的料。
    json.discard_reason lead.raw['discard_reason']
  end
end
