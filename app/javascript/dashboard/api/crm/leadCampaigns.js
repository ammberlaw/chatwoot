/* global axios */
import { buildCrmClient } from './_crmClient';

const api = buildCrmClient('lead_campaigns');

// 生成客户画像：不调 Apollo、不花 credits，料全来自我们自己的成交数据。
api.buildProfile = id => axios.post(`${api.url}/${id}/build_profile`);

// 按关键词搜潜在客户。搜索阶段不扣 credits（只拿到公司 + 名字半遮的联系人），
// 真邮箱要人点了才解锁。一次跑三五分钟，前端要给足等待提示。
api.search = id => axios.post(`${api.url}/${id}/search`);
api.leads = id => axios.get(`${api.url}/${id}/leads`);

// 获客效果：搜索词 → 线索 → 建档 → 成交额。不带 campaign_id 就是全部任务的累计。
api.outcomes = params => axios.get(`${api.url}/outcomes`, { params });

// 共享线索池：跨任务的待领线索。scope=pool 池子里（默认）/ mine 我领的。
// 池子是按「谁领谁得」设计的，但界面按任务组织——没有这个入口，
// 业务员想领一条得一个任务一个任务翻。
api.pool = scope => axios.get(`${api.url}/pool`, { params: { scope } });

// 管理端：这条线上每个人在干什么（谁领了多少、压了多久、转化率）。
// 只有经理/副管/管理员调得通，业务员会拿到 403。
api.teamStats = () => axios.get(`${api.url}/team_stats`);

// 全公司已验证的搜索词库，从各任务的真实战绩现算。建任务时直接挑。
api.keywordLibrary = () => axios.get(`${api.url}/keyword_library`);

export default api;
