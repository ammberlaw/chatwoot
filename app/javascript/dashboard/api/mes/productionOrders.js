/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('production_orders');

// 从销售订单一键转生产订单（脊柱起点）。
client.convert = payload => axios.post(`${client.url}/convert`, payload);

// 挂工程 BOM → 进 BOM_READY。
client.attachBom = (id, payload) =>
  axios.post(`${client.url}/${id}/attach_bom`, payload);

// 解除 BOM 关联（挂错了重挂）→ 退回「待工程接单」。
client.detachBom = id => axios.post(`${client.url}/${id}/detach_bom`);

// 采购原料退回工程/PMC BOM 阶段。
client.revertToBomReady = id =>
  axios.post(`${client.url}/${id}/revert_to_bom_ready`);

// 下发到采购阶段（BOM_READY → PURCHASING）。
client.releasePurchasing = id =>
  axios.post(`${client.url}/${id}/release_purchasing`);

// 工程标记外购：选定产品+供应商，跳过 BOM 直接进采购（短版脊柱）。
client.markOutsourced = (id, payload) =>
  axios.post(`${client.url}/${id}/mark_outsourced`, payload);

// 按 BOM 推料需求（生产领料预填）。
client.requirement = id => axios.get(`${client.url}/${id}/requirement`);

// 生产领料计划：BOM 推料 + 每行已领量/实时库存/待领量（warehouseId 传入算该仓库存）。
client.issuePlan = (id, warehouseId) =>
  axios.get(`${client.url}/${id}/issue_plan`, {
    params: { warehouse_id: warehouseId || undefined },
  });

// 接单 / 拒收打回（P1 接单确认）。
client.acknowledge = id => axios.post(`${client.url}/${id}/acknowledge`);
// 转给同阶段另一位负责人（工程 ↔ PMC 接力）：转出后接单状态清空，接收人重新收到待接单。
client.handoff = (id, payload) =>
  axios.post(`${client.url}/${id}/handoff`, payload);
client.reject = (id, reason) =>
  axios.post(`${client.url}/${id}/reject`, { reason });

// 业务转发/知会：把订单知会给某阶段负责人（board_key）+ 附言，推站内通知并在订单上留痕。
client.forward = (id, payload) =>
  axios.post(`${client.url}/${id}/forward`, payload);

// 我的待办：停在我负责阶段的在产订单。
client.inbox = () => axios.get(`${client.url}/inbox`);

// 审批链（取代发布）：提交 / 通过 / 驳回 / 待我审批收件箱。
client.submitApproval = id => axios.post(`${client.url}/${id}/submit_approval`);
client.approve = (id, comment) =>
  axios.post(`${client.url}/${id}/approve`, { comment });
client.deny = (id, reason) =>
  axios.post(`${client.url}/${id}/deny`, { reason });
client.approvalInbox = () => axios.get(`${client.url}/approval_inbox`);

// 首页 MES 入口卡的角标：只要数字，不拉整份列表。
client.todoCount = () => axios.get(`${client.url}/todo_count`);

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
