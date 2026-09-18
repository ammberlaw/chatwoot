<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import CustomerAPI from 'dashboard/api/crm/customers';
import { useCrmSalesOrdersStore } from 'dashboard/stores/crm/salesOrders';
import CrmSalesOrderCreateDialog from 'dashboard/components-next/CRM/CrmSalesOrderCreateDialog.vue';

import Button from 'dashboard/components-next/button/Button.vue';

// 历史 PI 补录：早期业务把 PI 直接传在客户「文件」页、没建销售订单，
// 那些金额不进成交口径（客户星级/成交额/成交订单数全都缺）。这里把它们盘出来逐条补建。
// 识别 PDF / xls / xlsx / csv。早年的 PI 大多是老版 .xls，后端走 Gotenberg
// 转 PDF 再抽文字，和新格式一样能识别，这里不再拦。
const store = useCrmSalesOrdersStore();
const rows = ref([]);
const loading = ref(true);
const parsingId = ref(null);
const orderDialogRef = ref(null);

const extOf = name => (name || '').toLowerCase().split('.').pop();
const isParsable = name => ['pdf', 'xls', 'xlsx', 'csv'].includes(extOf(name));

const kb = size => `${Math.max(1, Math.round((size || 0) / 1024))} KB`;

// 先列「该客户还没有成交订单」的——这些是账面缺口最明确的。
const sorted = computed(() =>
  [...rows.value].sort(
    (a, b) =>
      a.deal_order_count - b.deal_order_count ||
      a.customer_name.localeCompare(b.customer_name)
  )
);
const stats = computed(() => ({
  total: rows.value.length,
  parsable: rows.value.filter(r => isParsable(r.filename)).length,
  noDeal: rows.value.filter(r => r.deal_order_count === 0).length,
}));

const load = async () => {
  loading.value = true;
  try {
    const { data } = await CustomerAPI.piAttachmentCandidates();
    rows.value = data.payload || [];
  } catch (error) {
    useAlert(error?.response?.data?.error || '加载失败');
  } finally {
    loading.value = false;
  }
};

// 识别成功后直接打开「新建销售订单」弹窗，字段填好、客户锁定为附件所属客户。
const parseAndOpen = async row => {
  if (!isParsable(row.filename)) {
    useAlert('这个格式识别不了，支持 PDF / Excel（.xls/.xlsx/.csv）');
    return;
  }
  parsingId.value = row.attachment_id;
  try {
    const { data } = await CustomerAPI.parseAttachment(
      row.customer_id,
      row.attachment_id
    );
    if (!data.recognized) {
      useAlert(data.reason || '未识别到 PI 内容');
      return;
    }
    orderDialogRef.value?.openWithParsedPi({
      parsed: data,
      customer: { id: row.customer_id, name: row.customer_name },
    });
  } catch (error) {
    useAlert(error?.response?.data?.reason || '识别失败，请稍后重试');
  } finally {
    parsingId.value = null;
  }
};

// 弹窗只负责收集表单，落库在这里（与销售订单页同款）。
// 建单成功后刷新：该客户成交订单数会变，列表里的「缺口」标记要跟着更新。
const createOrder = async payload => {
  try {
    await store.create(payload);
    orderDialogRef.value?.onSuccess();
    useAlert('已补建销售订单，客户成交额与星级已更新');
    load();
  } catch (error) {
    useAlert(error?.message || '补建订单失败');
  }
};

onMounted(load);
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div class="w-full px-4 py-4 mx-auto max-w-6xl sm:px-8 sm:py-6">
      <h1 class="text-[22px] font-bold tracking-[-0.01em] text-n-slate-12">
        历史 PI 补录
      </h1>
      <p class="mt-1 mb-5 text-sm text-n-slate-11">
        早期直接传在客户「文件」页的 PI
        没有对应销售订单，金额不计入成交额，客户星级也评不出来。这里逐条识别、补建订单。
      </p>

      <div
        class="flex flex-wrap items-center gap-4 px-4 py-3 mb-4 text-sm rounded-xl bg-n-alpha-1"
      >
        <span class="text-n-slate-11">
          共
          <b class="text-n-slate-12">{{ stats.total }}</b>
          份 PI 附件
        </span>
        <span class="text-n-slate-11">
          可识别
          <b class="text-n-teal-11">{{ stats.parsable }}</b>
          份
        </span>
        <span class="text-n-slate-11">
          其中客户零成交
          <b class="text-n-amber-11">{{ stats.noDeal }}</b>
          份
        </span>
      </div>

      <div v-if="loading" class="py-10 text-sm text-center text-n-slate-10">
        加载中…
      </div>

      <div v-else class="overflow-x-auto border rounded-xl border-n-weak">
        <table class="w-full text-sm">
          <thead class="bg-n-alpha-1 text-n-slate-11">
            <tr>
              <th class="px-4 py-3 font-medium text-left">客户</th>
              <th class="px-4 py-3 font-medium text-left">PI 文件</th>
              <th class="px-4 py-3 font-medium text-right">大小</th>
              <th class="px-4 py-3 font-medium text-left">该客户成交单</th>
              <th class="px-4 py-3 font-medium text-right">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in sorted"
              :key="row.attachment_id"
              class="border-t border-n-weak hover:bg-n-alpha-1"
            >
              <td class="px-4 py-3 text-n-slate-12">{{ row.customer_name }}</td>
              <td class="px-4 py-3 text-n-slate-11">
                {{ row.filename }}
                <span
                  v-if="!isParsable(row.filename)"
                  class="ml-1 text-xs text-n-amber-11"
                >
                  不支持的格式
                </span>
              </td>
              <td class="px-4 py-3 text-right text-n-slate-11">
                {{ kb(row.byte_size) }}
              </td>
              <td class="px-4 py-3">
                <span
                  v-if="row.deal_order_count === 0"
                  class="px-2 py-0.5 text-xs rounded-full bg-n-amber-3 text-n-amber-11"
                >
                  0 单（账面缺口）
                </span>
                <span v-else class="text-n-slate-11">
                  {{ row.deal_order_count }} 单
                </span>
              </td>
              <td class="px-4 py-3 text-right whitespace-nowrap">
                <Button
                  :label="
                    parsingId === row.attachment_id ? '识别中…' : '识别并补单'
                  "
                  variant="ghost"
                  size="xs"
                  :disabled="parsingId !== null"
                  @click="parseAndOpen(row)"
                />
              </td>
            </tr>
            <tr v-if="!sorted.length">
              <td colspan="5" class="px-4 py-12 text-center text-n-slate-10">
                没有发现传在客户文件里的 PI，历史账已经补齐了。
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <CrmSalesOrderCreateDialog ref="orderDialogRef" @create="createOrder" />
  </div>
</template>
