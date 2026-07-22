/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('production_orders');

// 从销售订单一键转生产订单（脊柱起点）。
client.convert = payload => axios.post(`${client.url}/convert`, payload);

// 挂工程 BOM → 进 BOM_READY。
client.attachBom = (id, payload) =>
  axios.post(`${client.url}/${id}/attach_bom`, payload);

// 业务二次确认 BOM（BOM_READY 段内的闸，确认后方可下发采购）。
client.confirmBom = id => axios.post(`${client.url}/${id}/confirm_bom`);

// 下发到采购阶段（BOM_READY → PURCHASING）。
client.releasePurchasing = id =>
  axios.post(`${client.url}/${id}/release_purchasing`);

// 按 BOM 推料需求（生产领料预填）。
client.requirement = id => axios.get(`${client.url}/${id}/requirement`);

// 接单 / 拒收打回（P1 接单确认）。
client.acknowledge = id => axios.post(`${client.url}/${id}/acknowledge`);
client.reject = (id, reason) =>
  axios.post(`${client.url}/${id}/reject`, { reason });

// 我的待办：停在我负责阶段的在产订单。
client.inbox = () => axios.get(`${client.url}/inbox`);

// 审批链（取代发布）：提交 / 通过 / 驳回 / 待我审批收件箱。
client.submitApproval = id => axios.post(`${client.url}/${id}/submit_approval`);
client.approve = (id, comment) =>
  axios.post(`${client.url}/${id}/approve`, { comment });
client.deny = (id, reason) =>
  axios.post(`${client.url}/${id}/deny`, { reason });
client.approvalInbox = () => axios.get(`${client.url}/approval_inbox`);

// 产品编码（工程/PMC 编，唯一，供 ERP 共享）。
client.setProductCode = (id, productCode) =>
  axios.post(`${client.url}/${id}/set_product_code`, {
    product_code: productCode,
  });

// 暂存文件为 blob（建单前即可上传），返回 { signed_id, filename, url }。
client.stageBlob = formData =>
  axios.post(`${client.url}/stage_blob`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

// 产品图片 / 附件上传下载。kind = 'images' | 'files'。
client.attachFiles = (id, formData, kind = 'files') =>
  axios.post(`${client.url}/${id}/attach?kind=${kind}`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
client.detachFile = (id, attachmentId, kind = 'files') =>
  axios.delete(`${client.url}/${id}/attach/${attachmentId}?kind=${kind}`);

export default client;
