/* global axios */
import { buildCrmClient } from './_crmClient';

const client = buildCrmClient('sales_targets');

// 目标体检：谁本月没设、谁当年合计低于保本线。仅管理员/副管/人事可调（后端 policy 收口）。
client.audit = year => axios.get(`${client.url}/audit`, { params: { year } });

// 一键按底线补缺的月份。source: recorded(薪资表底线) | suggested(系统建议值)
client.seed = payload => axios.post(`${client.url}/seed`, payload);

export default client;
