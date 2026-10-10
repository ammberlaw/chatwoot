/* global axios */
import { buildMesClient } from './_mesClient';
import { withReturnActions } from './_returnable';

const client = withReturnActions(buildMesClient('purchase_orders'));

// BOM 算料：按生产订单展开采购需求，供采购单预填。
// category 可选：MACHINE 主料(整机料) / PACKAGING 辅料(包装料)——两个采购员分料建单。
client.requirement = (productionOrderId, category = '') =>
  axios.get(`${client.url}/requirement`, {
    params: {
      production_order_id: productionOrderId,
      category: category || undefined,
    },
  });

// 审批链（总经理一级）：提交/通过/驳回 + 待我审批箱。
client.submit = id => axios.post(`${client.url}/${id}/submit`);
client.approve = (id, comment = '') =>
  axios.post(`${client.url}/${id}/approve`, { comment });
client.reject = (id, reason = '') =>
  axios.post(`${client.url}/${id}/reject`, { reason });
client.approvalInbox = () => axios.get(`${client.url}/approval_inbox`);

// 明细行内部附图：先把图传上来拿 signed_id，随明细一起提交（后端 images= 整组替换）。
client.stageBlob = formData =>
  axios.post(`${client.url}/stage_blob`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

export default client;
