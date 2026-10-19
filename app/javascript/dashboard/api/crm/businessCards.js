/* global axios */
import { buildCrmClient } from './_crmClient';

const api = buildCrmClient('business_cards');

// 自己最近用过的展会名称：拍下一张时直接点，不用每次重打。
api.events = () => axios.get(`${api.url}/events`);
// 确认入库。不带参数＝建新客户（撞到重复会回 409）；
// force=true 明知重复也要另建；link_customer_id=挂到已有客户上，不建新的。
api.confirm = (id, params = {}) =>
  axios.post(`${api.url}/${id}/confirm`, params);

export default api;
