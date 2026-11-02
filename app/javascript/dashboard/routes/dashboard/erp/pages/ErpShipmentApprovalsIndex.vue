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

// 单价 vs 上次成交：财务放行前一眼看出这价异不异常。
// 数据由后端在出库单详情里算好（Crm::PriceBenchmark，按品名比、同客户优先）。
// normal 不出文案——没异常就别占地方。
const priceHint = item => {
  const b = item.price_benchmark;
  if (!b || b.level === 'normal') return null;
  const pct = Math.abs(Math.round(b.diff_ratio * 100));
  return {
    level: b.level,
    text: `系统提示：比${b.scope_label}${b.diff_ratio > 0 ? '高' : '低'} ${pct}%`,
    title: `${b.scope_label}：${b.order_no}（${(b.order_date || '').slice(0, 10)}）单价 ${b.last_price}`,
  };
};
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

// 只到日，审核看的是「几号下的单、几号要交货」，时分秒是噪音。
const day = v => (v ? String(v).slice(0, 10) : '');
// 整行都没内容就别占那 mt-2 的空档（生产出库单常常没挂销售订单）。
const hasOrderMeta = s =>
  s.sales_order_amount_micros != null ||
  s.sales_order_date ||
  s.sales_delivery_date ||
  s.delivery_method_label ||
  s.owner_name ||
  s.submitted_at ||
  s.sales_order_remark ||
  s.remark;

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
  <div class="flex flex-col w-full h-full min-h-0 bg-white">
    <div
      class="flex items-center justify-between px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:sm:!px-8"
    >
      <div class="flex items-baseline gap-2">
        <h1
          class="text-heading-1 text-n-slate-12"
        >
          出库审核
        </h1>
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
      <div v-else class="flex flex-col gap-4">
        <div
          v-for="s in records"
          :key="s.id"
          class="overflow-hidden p-4 sm:p-5 border rounded-2xl border-n-weak bg-white"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span class="text-heading-2 text-n-slate-12">{{ s.shipment_no }}</span>
            <span
              class="px-2 py-0.5 text-xs rounded-full bg-n-slate-3 text-n-slate-11"
            >
              {{ s.kind === 'STOCK' ? '现货出库' : '生产出库' }}
            </span>
            <!-- 小额单（≤5000 美金 / 3 万人民币）仓库自己就能批，不用财务逐张看。
                 仍列在这里是留个兜底：仓库没动的，财务照样批得了。 -->
            <span
              v-if="s.warehouse_self_approvable"
              class="px-2 py-0.5 text-xs rounded-full bg-n-teal-3 text-n-teal-11"
            >
              仓库可批
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
              variant="outline"
              color="ruby"
              size="sm"
              @click="openReject(s)"
            />
          </div>

          <div class="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 border-b border-n-weak pb-3 text-label-small">
            <span class="text-label font-medium text-n-slate-12">
              {{ s.customer_name || '—' }}
            </span>
            <span
              v-if="s.sales_order_no"
              class="tabular-nums text-xs text-n-slate-10"
            >
              {{ s.sales_order_no }}
            </span>
            <!-- 没挂销售订单的生产出库单，生产单号是唯一能往回追的线索 -->
            <span
              v-else-if="s.production_order_no"
              class="tabular-nums text-xs text-n-slate-10"
            >
              {{ s.production_order_no }}
            </span>
            <span class="text-xs text-n-slate-11">
              业务
              <b class="ml-0.5 text-n-slate-12">
                {{ s.sales_owner_name || '—' }}
              </b>
            </span>
          </div>

          <!-- 单据头：本次出库往往只是整张订单的一车，财务要对得上订单总额和交期；
               制单/提交是出了问题该找谁。备注独占一行（客户的特别交代常写在这）。 -->
          <div
            v-if="hasOrderMeta(s)"
            class="flex flex-wrap items-center mt-3 text-label-small gap-x-5 gap-y-1.5 text-n-slate-11"
          >
            <!-- 货款与运费分开列，再给一个合计。订单金额字段本身**不含运费**，
                 卡片上只摆一个「订单金额」，财务拿它对收款就差一笔运费对不上
                 （审核弹窗里早就是三行，卡片漏了同一套处理；用户 2026-11-02 反馈）。 -->
            <span v-if="s.sales_order_amount_micros != null">
              货款
              <b class="ml-1 tabular-nums text-n-slate-12">
                {{ money(s.sales_order_amount_micros, s.sales_order_currency) }}
              </b>
            </span>
            <span v-if="s.sales_shipping_micros">
              运费
              <b class="ml-1 tabular-nums text-n-slate-12">
                {{ money(s.sales_shipping_micros, s.sales_order_currency) }}
              </b>
            </span>
            <span v-if="s.sales_shipping_micros">
              客户应付合计
              <b class="ml-1 tabular-nums text-n-slate-12">
                {{ money(s.sales_gross_micros, s.sales_order_currency) }}
              </b>
            </span>
            <span v-if="day(s.sales_order_date)">
              下单 {{ day(s.sales_order_date) }}
            </span>
            <span v-if="day(s.sales_delivery_date)">
              交期 {{ day(s.sales_delivery_date) }}
            </span>
            <span v-if="s.delivery_method_label">
              交货
              <b class="ml-1 text-n-slate-12">{{ s.delivery_method_label }}</b>
            </span>
            <span v-if="s.owner_name">制单 {{ s.owner_name }}</span>
            <span v-if="day(s.submitted_at)">
              提交 {{ day(s.submitted_at) }}
            </span>
            <span v-if="s.sales_order_remark" class="w-full leading-5">
              订单备注 {{ s.sales_order_remark }}
            </span>
            <span v-if="s.remark" class="w-full">出库备注 {{ s.remark }}</span>
          </div>

          <!-- 收款情况：财务放不放行就看这一行 -->
          <div
            v-if="s.receivable_state"
            class="flex flex-wrap items-center gap-x-5 gap-y-2 px-3 py-3 mt-3 text-label-small rounded-lg border"
            :class="unpaidOf(s) ? 'bg-[#fffaf0] border-[#f1e6c7]' : 'bg-n-alpha-1 border-n-weak'"
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
              {{ unpaidOf(s) ? '未收金额' : '已收齐' }}
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

          <!-- 收款约定：按什么方式收、收到哪个户、信保单号多少。
               ⚠️ 这一组**不能**跟着上面的应收块一起条件渲染：原来整组写在
               `v-if="s.receivable_state"` 里，订单没在财务建账时连信保单号一起藏掉——
               而恰恰是没建账的单，财务才最需要这个号去阿里平台对出是哪一笔
               （用户 2026-11-02 反馈「没有信保订单号，不知道是哪个订单的」）。 -->
          <div
            v-if="
              s.payment_term_label ||
              s.receipt_account_name ||
              s.insurance_order_no
            "
            class="flex flex-wrap items-center gap-x-5 gap-y-2 mt-2 text-label-small"
          >
            <span v-if="s.payment_term_label" class="text-n-slate-11">
              结算
              <b class="ml-1 text-n-slate-12">{{ s.payment_term_label }}</b>
            </span>
            <span v-if="s.receipt_account_name" class="text-n-slate-11">
              收款账户
              <b class="ml-1 text-n-slate-12">{{ s.receipt_account_name }}</b>
            </span>
            <span v-if="s.insurance_order_no" class="text-n-slate-11">
              信保单号
              <b class="ml-1 text-n-slate-12">{{ s.insurance_order_no }}</b>
            </span>
          </div>

          <!-- 收过哪几笔：日期 / 途径 / 金额。财务对着银行流水核完才批。
               金额是冲到**这张订单**上的那部分，一笔款冲几张订单时不会重复计。 -->
          <table
            v-if="s.receipts && s.receipts.length"
            class="w-full mt-3 text-label !font-normal [&_td]:py-2 [&_th]:text-label-small"
          >
            <thead>
              <tr class="text-left text-n-slate-11">
                <th class="px-3 py-1 font-medium whitespace-nowrap">收款日期</th>
                <th class="px-3 py-1 font-medium whitespace-nowrap">途径</th>
                <th class="px-3 py-1 font-medium whitespace-nowrap">收款账户</th>
                <th class="px-3 py-1 font-medium whitespace-nowrap">水单号</th>
                <th
                  class="px-3 py-1 font-medium text-right whitespace-nowrap"
                >
                  收款金额
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="r in s.receipts"
                :key="r.receipt_no"
                class="border-t border-n-weak"
              >
                <td class="px-3 py-1 whitespace-nowrap text-n-slate-12">
                  {{ r.received_at }}
                </td>
                <td class="px-3 py-1 whitespace-nowrap text-n-slate-12">
                  {{ r.method_label || '—' }}
                </td>
                <td class="px-3 py-1 whitespace-nowrap text-n-slate-11">
                  {{ r.account_name || '—' }}
                </td>
                <td class="px-3 py-1 whitespace-nowrap text-n-slate-11">
                  {{ r.reference_no || '—' }}
                </td>
                <td
                  class="px-3 py-1 font-medium text-right tabular-nums whitespace-nowrap text-n-slate-12"
                >
                  {{ money(r.amount_micros, r.currency) }}
                </td>
              </tr>
            </tbody>
          </table>
          <div
            v-else-if="s.receivable_state && s.receivable_state.received_micros"
            class="px-3 py-1 mt-1 text-xs text-n-slate-11"
          >
            已收 {{ money(s.receivable_state.received_micros, s.receivable_state.currency) }}，但没有对应的收款记录
          </div>

          <div
            v-else-if="!s.receivable_state"
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
          <div v-if="s.shipment_items?.length" class="mt-4 overflow-x-auto">
            <table class="w-full text-label !font-normal min-w-[520px] [&_td]:py-2.5 [&_th]:py-2 [&_th]:text-label-small">
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
                  <td class="py-1 pr-3 tabular-nums">
                    {{ it.product_sku || '—' }}
                  </td>
                  <td class="py-1 pr-3 font-medium text-n-slate-12">
                    {{ it.product_name || '—' }}
                  </td>
                  <td class="py-1 pr-3">{{ it.specification || '—' }}</td>
                  <td class="py-1 pr-3 text-right tabular-nums">
                    {{ Number(it.qty || 0) }} {{ it.unit || '' }}
                  </td>
                  <td class="py-1 pr-3 text-right tabular-nums whitespace-nowrap">
                    {{ it.unit_price == null ? '—' : Number(it.unit_price) }}
                    <!-- 跟上次成交比高了还是低了。正常就不出字，没异常别占地方。 -->
                    <span
                      v-if="priceHint(it)"
                      class="mt-1 block text-label-small"
                      :class="
                        priceHint(it).level === 'alert'
                          ? 'text-n-ruby-11 font-medium'
                          : 'text-n-amber-11'
                      "
                      :title="priceHint(it).title"
                    >
                      {{ priceHint(it).text }}
                    </span>
                  </td>
                  <td class="py-1 text-right tabular-nums text-n-slate-12">
                    {{ it.amount == null ? '—' : Number(it.amount).toFixed(2) }}
                  </td>
                </tr>
              </tbody>
            </table>
            <div
              class="flex flex-wrap items-center gap-x-5 gap-y-2 pt-3 mt-1 text-label-small border-t border-n-weak text-n-slate-11"
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
        <!-- 财务审的是「这单该收多少、收齐没有」，所以订单号和金额要摆在眼前。
             货款和运费分开列：订单金额不含运费，只给货款会和收款对不上。 -->
        <div
          class="grid grid-cols-2 gap-x-6 gap-y-1.5 px-3 py-2 text-sm rounded-lg bg-n-alpha-1"
        >
          <div class="flex justify-between">
            <span class="text-n-slate-11">销售订单</span>
            <span class="tabular-nums text-n-slate-12">
              {{
                approving.sales_order_no || approving.production_order_no || '—'
              }}
            </span>
          </div>
          <div class="flex justify-between">
            <span class="text-n-slate-11">业务员</span>
            <span class="text-n-slate-12">
              {{ approving.sales_owner_name || '—' }}
            </span>
          </div>
          <div class="flex justify-between">
            <span class="text-n-slate-11">货款</span>
            <span class="tabular-nums text-n-slate-12">
              {{
                money(
                  approving.sales_order_amount_micros,
                  approving.sales_order_currency
                )
              }}
            </span>
          </div>
          <div class="flex justify-between">
            <span class="text-n-slate-11">运费</span>
            <span class="tabular-nums text-n-slate-12">
              {{
                money(
                  approving.sales_shipping_micros,
                  approving.sales_order_currency
                )
              }}
            </span>
          </div>
          <div
            class="flex justify-between col-span-2 pt-1.5 border-t border-n-weak"
          >
            <span class="text-n-slate-11">客户应付合计</span>
            <span class="tabular-nums font-medium text-n-slate-12">
              {{
                money(
                  approving.sales_gross_micros,
                  approving.sales_order_currency
                )
              }}
            </span>
          </div>
        </div>
        <div v-if="unpaidOf(approving)" class="flex flex-col gap-2">
          <label class="text-heading-3 text-n-slate-12">
            款没收齐，放行理由 <span class="text-n-ruby-11">*</span>
          </label>
          <Input v-model="approveNote" placeholder="放行理由" />
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
