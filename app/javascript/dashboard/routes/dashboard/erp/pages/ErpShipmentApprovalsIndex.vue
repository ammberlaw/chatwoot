<script setup>
// 出库审核（财务）：放货前核对「款收齐没有」。
//
// 用户给的金蝶流程：业务下销售订单 → 主管审核 → 推到仓库 → **财务审核是否收齐全款** → 出库。
// 审核动作本身在 MES 的销售出库页也能做，但财务没有 MES 角色、本来就在 ERP 里干活，
// 让他为了批一张单去 MES 翻列表不现实——所以在 ERP 开这个入口，只列等他批的那些。
//
// 数据走 MES 的出库接口（财务对 MES 后端是放行的，Mes::Shipment.approver? 把关谁能批），
// 不另起一套单据模型——两套状态迟早对不上。
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import MesShipmentAPI from 'dashboard/api/mes/shipments';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const records = ref([]);
const loading = ref(false);
const acting = ref(false);

// 金额是 micros（百万分之一），带千分位——外贸的数动辄六七位。
const money = (micros, currency) =>
  `${currency || ''} ${(Number(micros || 0) / 1e6).toLocaleString('zh-CN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`.trim();

const fetchList = async () => {
  loading.value = true;
  try {
    // with_receivable=1：列表上直接看到「还差多少」，不用逐张点开（普通出库列表不带，
    // 逐行跑回款进度是 N+1）。
    const { data } = await MesShipmentAPI.get({
      status: 'PENDING_APPROVAL',
      with_receivable: 1,
      per_page: 100,
    });
    records.value = data.payload || [];
  } catch {
    records.value = [];
  } finally {
    loading.value = false;
  }
};
onMounted(fetchList);

const unpaidOf = s => s.fully_paid === false;
// 本次出库的货值：按行的 amount 合计（amount 已按本次出库量算，不是订单量）。
// 有行取不到单价时合计标成「含未计价行」，不要给一个少算了的数让人以为就这么多。
const itemsTotal = s => {
  const rows = s.shipment_items || [];
  const sum = rows.reduce((a, r) => a + Number(r.amount || 0), 0);
  const missing = rows.some(r => r.amount == null);
  const text = sum.toLocaleString('zh-CN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  return missing ? `${text}（含未计价行）` : text;
};

const pendingCount = computed(() => records.value.length);

// —— 审核通过：款没收齐要写理由 ——
const approveDialogRef = ref(null);
const approving = ref(null);
const approveNote = ref('');
const openApprove = s => {
  approving.value = s;
  approveNote.value = '';
  approveDialogRef.value?.open();
};
const submitApprove = async () => {
  if (unpaidOf(approving.value) && !approveNote.value.trim()) return;
  acting.value = true;
  try {
    await MesShipmentAPI.approve(
      approving.value.id,
      approveNote.value.trim() || undefined
    );
    useAlert(`${approving.value.shipment_no} 已审核通过，已推仓库`);
    approveDialogRef.value?.close();
    await fetchList();
  } catch (e) {
    useAlert(e?.response?.data?.error || '审核失败');
  } finally {
    acting.value = false;
  }
};

// —— 驳回：必须写原因 ——
const rejectDialogRef = ref(null);
const rejecting = ref(null);
const rejectReason = ref('');
const openReject = s => {
  rejecting.value = s;
  rejectReason.value = '';
  rejectDialogRef.value?.open();
};
const submitReject = async () => {
  if (!rejectReason.value.trim()) return;
  acting.value = true;
  try {
    await MesShipmentAPI.reject(rejecting.value.id, rejectReason.value.trim());
    useAlert(`${rejecting.value.shipment_no} 已驳回`);
    rejectDialogRef.value?.close();
    await fetchList();
  } catch (e) {
    useAlert(e?.response?.data?.error || '驳回失败');
  } finally {
    acting.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      class="flex items-center justify-between px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:sm:!px-8"
    >
      <div class="flex items-baseline gap-2">
        <h1
          class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1"
        >
          出库审核
        </h1>
        <span class="text-xs text-n-slate-11">
          放货前核对这张单的款收齐没有
        </span>
      </div>
      <span
        v-if="pendingCount"
        class="px-2 py-0.5 text-xs rounded-full bg-n-amber-3 text-n-amber-11"
      >
        {{ pendingCount }} 张待审核
      </span>
    </div>

    <div
      class="flex-1 min-h-0 px-4 pb-4 overflow-auto sm:px-6 sm:pb-6 [.theme-classic_&]:sm:!px-8"
    >
      <div v-if="loading" class="py-10 text-sm text-center text-n-slate-11">
        加载中…
      </div>
      <div
        v-else-if="!records.length"
        class="py-16 text-sm text-center text-n-slate-10"
      >
        没有等你审核的出库单。
      </div>
      <div v-else class="flex flex-col gap-2">
        <div
          v-for="s in records"
          :key="s.id"
          class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span class="font-medium text-n-slate-12">{{ s.shipment_no }}</span>
            <span
              class="px-2 py-0.5 text-xs rounded-full bg-n-slate-3 text-n-slate-11"
            >
              {{ s.kind === 'STOCK' ? '现货出库' : '生产出库' }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ s.customer_name || '—' }}
            </span>
            <span
              v-if="s.sales_order_no"
              class="font-mono text-xs text-n-slate-10"
            >
              {{ s.sales_order_no }}
            </span>
            <span class="flex-1" />
            <Button
              label="审核通过"
              color="iris"
              size="sm"
              :is-loading="acting"
              @click="openApprove(s)"
            />
            <Button
              label="驳回"
              variant="ghost"
              color="ruby"
              size="sm"
              @click="openReject(s)"
            />
          </div>

          <!-- 收款情况：财务放不放行就看这一行 -->
          <div
            v-if="s.receivable_state"
            class="flex flex-wrap items-center gap-x-5 gap-y-1 px-3 py-2 mt-2 text-xs rounded-lg"
            :class="unpaidOf(s) ? 'bg-n-amber-2' : 'bg-n-teal-2'"
          >
            <span class="text-n-slate-11">
              应收
              <b class="ml-1 tabular-nums text-n-slate-12">
                {{
                  money(
                    s.receivable_state.total_micros,
                    s.receivable_state.currency
                  )
                }}
              </b>
            </span>
            <span class="text-n-slate-11">
              已收
              <b class="ml-1 tabular-nums text-n-slate-12">
                {{
                  money(
                    s.receivable_state.received_micros,
                    s.receivable_state.currency
                  )
                }}
              </b>
            </span>
            <span :class="unpaidOf(s) ? 'text-n-amber-11' : 'text-n-teal-11'">
              {{ unpaidOf(s) ? '还差' : '已收齐' }}
              <b class="ml-1 tabular-nums">
                {{
                  money(
                    s.receivable_state.outstanding_micros,
                    s.receivable_state.currency
                  )
                }}
              </b>
            </span>
          </div>
          <div
            v-else
            class="px-3 py-2 mt-2 text-xs rounded-lg text-n-slate-11 bg-n-alpha-1"
          >
            <template v-if="s.sales_order_no">
              {{ s.sales_order_no }}
              还没在财务建账（应收台账里没有这张单），系统查不到
              收款情况。先去「应收台账」建账，或自行核对后放行。
            </template>
            <template v-else>
              这张单没挂销售订单，系统查不到收款情况，请自行核对后再放行。
            </template>
          </div>

          <!-- 货物明细：财务要知道这一车放的是什么、值多少钱才敢签字。
               数据接口本来就带（shipment_items），原先这页没渲染，只有一个单号和两个按钮
               （10.20 反馈「这个出库审核没有单据详情，审核不了」）。 -->
          <div v-if="s.shipment_items?.length" class="mt-2 overflow-x-auto">
            <table class="w-full text-xs min-w-[520px]">
              <thead>
                <tr class="text-left text-n-slate-10">
                  <th class="py-1 pr-3 font-medium">商品编码</th>
                  <th class="py-1 pr-3 font-medium">品名</th>
                  <th class="py-1 pr-3 font-medium">规格</th>
                  <th class="py-1 pr-3 font-medium text-right">数量</th>
                  <th class="py-1 pr-3 font-medium text-right">单价</th>
                  <th class="py-1 font-medium text-right">金额</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="it in s.shipment_items"
                  :key="it.id"
                  class="border-t border-n-weak text-n-slate-11"
                >
                  <td class="py-1 pr-3 font-mono">
                    {{ it.product_sku || '—' }}
                  </td>
                  <td class="py-1 pr-3 text-n-slate-12">
                    {{ it.product_name || '—' }}
                  </td>
                  <td class="py-1 pr-3">{{ it.specification || '—' }}</td>
                  <td class="py-1 pr-3 text-right tabular-nums">
                    {{ Number(it.qty || 0) }} {{ it.unit || '' }}
                  </td>
                  <td class="py-1 pr-3 text-right tabular-nums">
                    {{ it.unit_price == null ? '—' : Number(it.unit_price) }}
                  </td>
                  <td class="py-1 text-right tabular-nums text-n-slate-12">
                    {{ it.amount == null ? '—' : Number(it.amount).toFixed(2) }}
                  </td>
                </tr>
              </tbody>
            </table>
            <div
              class="flex flex-wrap items-center gap-x-5 gap-y-1 pt-1 mt-1 text-xs border-t border-n-weak text-n-slate-11"
            >
              <span>
                本次出库合计
                <b class="ml-1 tabular-nums text-n-slate-12">
                  {{ itemsTotal(s) }}
                </b>
              </span>
              <span v-if="s.warehouse_name">发货仓 {{ s.warehouse_name }}</span>
              <span v-if="s.customer_address">
                交货地点 {{ s.customer_address }}
              </span>
            </div>
          </div>
          <div
            v-else
            class="px-3 py-2 mt-2 text-xs rounded-lg text-n-amber-11 bg-n-amber-2"
          >
            这张单没有出库明细，核对不了放的是什么货——先回销售出库页确认单据是否建完整。
          </div>
        </div>
      </div>
    </div>

    <Dialog
      ref="approveDialogRef"
      :dismissible="false"
      width="md"
      title="确认放行出库"
      confirm-button-label="审核通过"
      :disable-confirm-button="
        approving && unpaidOf(approving) && !approveNote.trim()
      "
      @confirm="submitApprove"
    >
      <div v-if="approving" class="flex flex-col gap-3">
        <p class="text-sm text-n-slate-11">
          {{ approving.shipment_no }} · {{ approving.customer_name || '—' }}
        </p>
        <div v-if="unpaidOf(approving)" class="flex flex-col gap-2">
          <label class="text-heading-3 text-n-slate-12">
            款没收齐，放行理由 <span class="text-n-ruby-11">*</span>
          </label>
          <Input
            v-model="approveNote"
            placeholder="例：老客户赊账，已报老板同意；或 尾款已汇在途"
          />
        </div>
        <p v-else class="text-sm text-n-teal-11">款已收齐，可以放行。</p>
      </div>
    </Dialog>

    <Dialog
      ref="rejectDialogRef"
      :dismissible="false"
      width="md"
      confirm-button-color="ruby"
      title="驳回出库单"
      :disable-confirm-button="!rejectReason.trim()"
      @confirm="submitReject"
    >
      <div class="flex flex-col gap-2">
        <label class="text-heading-3 text-n-slate-12">
          驳回原因 <span class="text-n-ruby-11">*</span>
        </label>
        <Input
          v-model="rejectReason"
          placeholder="请填写驳回原因，退回业务员"
        />
      </div>
    </Dialog>
  </div>
</template>
