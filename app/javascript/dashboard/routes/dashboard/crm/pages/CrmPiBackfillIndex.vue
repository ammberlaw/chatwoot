<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import CustomerAPI from 'dashboard/api/crm/customers';
import SalesOrdersAPI from 'dashboard/api/crm/salesOrders';
import { useCrmSalesOrdersStore } from 'dashboard/stores/crm/salesOrders';
import CrmSalesOrderCreateDialog from 'dashboard/components-next/CRM/CrmSalesOrderCreateDialog.vue';

import Button from 'dashboard/components-next/button/Button.vue';
import { isClassicTheme } from 'dashboard/components-next/CRM/charts/chartColors';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
// 历史 PI 补录：早期业务把 PI 直接传在客户「文件」页、没建销售订单，
// 那些金额不进成交口径（客户星级/成交额/成交订单数全都缺）。这里把它们盘出来逐条补建。
// 识别 PDF / xls / xlsx / csv。早年的 PI 大多是老版 .xls，后端走 Gotenberg
// 转 PDF 再抽文字，和新格式一样能识别，这里不再拦。
// 经典灰把 iris/blue 重定义成灰色，主行动按钮在那儿会塌成灰；teal 又和经典灰的暖色调不搭。
// 沿用客户列表那套约定：经典灰下主行动走 amber(金黄)，其它主题保持原色。
const isClassic = ref(isClassicTheme());
const goColor = computed(() => (isClassic.value ? 'amber' : 'teal'));
const goText = computed(() =>
  isClassic.value ? 'text-n-amber-11' : 'text-n-teal-11'
);

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

// ---- 批量上传历史 PI ----
// 上面那张表只捞得到「已经传在客户文件页」的 PI。客户压根没建档的（小单客户常见）
// 就完全够不着，历史订单额也就统计不出来。这里直接传文件批量补。
//
// 识别一份要调一次 AI（约 2 秒），二十份就是四十秒——放后端会撞生产 15 秒超时，
// 所以逐个调现成的 parse_pi 接口，在前端串起来，顺带能显示进度。
const picked = ref([]); // { file, name, status, parsed, customerChoice, newCustomerName, orderNo }
const batchInput = ref(null);
const parsing = ref(false);
const creating = ref(false);
const parseDone = computed(
  () => picked.value.filter(p => p.status !== 'pending').length
);
const readyRows = computed(() => picked.value.filter(p => p.status === 'ok'));

const money = (amount, currency) =>
  amount == null ? '—' : `${currency || ''} ${Number(amount).toLocaleString()}`;

const onPickFiles = async event => {
  const files = Array.from(event.target.files || []).filter(f =>
    isParsable(f.name)
  );
  event.target.value = '';
  if (!files.length) {
    useAlert('没有可识别的文件，支持 PDF / Excel（.xls/.xlsx/.csv）');
    return;
  }
  picked.value = files.map(f => ({
    file: f,
    name: f.name,
    status: 'pending',
    parsed: null,
    reason: '',
    customerChoice: 'new', // new | existing | none
    orderNo: '',
  }));
  await parseAll();
};

const parseAll = async () => {
  parsing.value = true;
  try {
    // 串行：AI 接口并发打上去容易被限流，也让进度看得清楚。
    for (const row of picked.value) {
      // eslint-disable-next-line no-await-in-loop
      await parseOne(row);
    }
  } finally {
    parsing.value = false;
  }
};

const parseOne = async row => {
  const fd = new FormData();
  fd.append('file', row.file);
  try {
    const { data } = await SalesOrdersAPI.parsePi(fd);
    row.parsed = data;
    row.status = 'ok';
    // 匹配上「我的客户」就直接沿用；没匹配上但认出了买方名才建新档；
    // 连买方名都没认出来（PI 版式怪的时候会这样）就只能先不关联，没名字建不了档。
    if (data?.customer?.matched_id) row.customerChoice = 'existing';
    else row.customerChoice = data?.customer?.raw_name ? 'new' : 'none';
  } catch (error) {
    row.status = 'failed';
    row.reason = error?.response?.data?.error || '识别失败';
  }
};

const removeRow = row => {
  picked.value = picked.value.filter(p => p !== row);
};

// 逐条建单：客户按每行的选择处理（沿用匹配到的 / 用买方名新建 / 不关联）。
// 不关联的单会落进侧栏「未关联客户的订单」，之后能再补挂客户。
const createAll = async () => {
  creating.value = true;
  let ok = 0;
  let failed = 0;
  try {
    for (const row of readyRows.value) {
      if (row.orderNo) continue; // 已建过的跳过，避免重复点重复建
      try {
        // eslint-disable-next-line no-await-in-loop
        row.orderNo = await createOneFromParsed(row);
        ok += 1;
      } catch (error) {
        row.status = 'failed';
        row.reason = error?.message || '补建失败';
        failed += 1;
      }
    }
  } finally {
    creating.value = false;
  }
  useAlert(`补建完成：成功 ${ok} 单${failed ? `，失败 ${failed} 单` : ''}`);
  load();
};

const createOneFromParsed = async row => {
  const p = row.parsed;
  const customerId = await resolveCustomerId(row);
  const order = await store.create({
    name: p.name || p.pi_no || row.name,
    piNo: p.pi_no || null,
    crmCustomerId: customerId,
    status: 'COMPLETED',
    orderDate: p.order_date || new Date().toISOString().slice(0, 10),
    deliveryDate: p.delivery_date || null,
    orderCurrency: p.currency || null,
    orderAmountMicros:
      p.amount == null ? null : Math.round(Number(p.amount) * 1_000_000),
    lineItemsJson: JSON.stringify(p.line_items || []),
    __files: [row.file],
  });
  return order?.orderNo || order?.order_no || '已建';
};

const resolveCustomerId = async row => {
  if (row.customerChoice === 'none') return null;
  if (row.customerChoice === 'existing')
    return row.parsed?.customer?.matched_id || null;

  const name = (row.parsed?.customer?.raw_name || '').trim();
  if (!name) return null;
  const { data } = await CustomerAPI.create({ customer: { name } });
  return data?.id || data?.payload?.id || null;
};

onMounted(load);
</script>

<template>
  <HScrollButtons />
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div class="w-full px-4 py-4 mx-auto max-w-6xl sm:px-8 sm:py-6">
      <h1 class="text-[22px] font-bold tracking-[-0.01em] text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">
        历史 PI 补录
      </h1>

      <!-- 批量上传：客户没建档的历史 PI 靠这里补，下面那张表只捞得到已传在客户文件页的。 -->
      <div class="p-4 mb-5 border rounded-2xl border-n-weak bg-n-solid-1/60">
        <div class="flex flex-wrap items-center gap-3">
          <Button
            label="上传历史 PI（可多选）"
            icon="i-lucide-upload"
            color="iris"
            size="sm"
            :is-loading="parsing"
            @click="batchInput?.click()"
          />
          <input
            ref="batchInput"
            type="file"
            multiple
            accept=".pdf,.xlsx,.xls,.csv"
            class="hidden"
            @change="onPickFiles"
          />
          <span v-if="parsing" class="text-sm text-n-slate-11">
            识别中 {{ parseDone }} / {{ picked.length }}…
          </span>
          <span v-else-if="picked.length" class="text-sm text-n-slate-11">
            已识别 {{ readyRows.length }} / {{ picked.length }} 份
          </span>
          <span class="flex-1" />
          <Button
            v-if="readyRows.length"
            :label="`全部补建（${readyRows.filter(r => !r.orderNo).length} 单）`"
            :color="goColor"
            size="sm"
            :is-loading="creating"
            :disabled="parsing || !readyRows.filter(r => !r.orderNo).length"
            @click="createAll"
          />
        </div>

        <HScrollButtons v-if="picked.length" />
        <div v-if="picked.length" class="mt-3 overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11">
                <th class="px-3 py-2 font-medium whitespace-nowrap">文件</th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">PI 号</th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">买方</th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">
                  客户归档
                </th>
                <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
                  金额
                </th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">日期</th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">状态</th>
                <th class="px-3 py-2" />
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in picked"
                :key="row.name"
                class="border-t border-n-weak"
              >
                <td class="px-3 py-2 max-w-[220px] truncate text-n-slate-12">
                  {{ row.name }}
                </td>
                <td class="px-3 py-2 font-mono text-n-slate-11">
                  {{ row.parsed?.pi_no || '—' }}
                </td>
                <td class="px-3 py-2 max-w-[180px] truncate text-n-slate-11">
                  {{ row.parsed?.customer?.raw_name || '—' }}
                </td>
                <td class="px-3 py-2">
                  <span v-if="row.status !== 'ok'" class="text-n-slate-10">
                    —
                  </span>
                  <span
                    v-else-if="row.parsed?.customer?.matched_id"
                    class="text-n-teal-11"
                  >
                    已匹配：{{ row.parsed.customer.matched_name }}
                  </span>
                  <select
                    v-else
                    v-model="row.customerChoice"
                    class="h-8 px-2 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12"
                  >
                    <option v-if="row.parsed?.customer?.raw_name" value="new">
                      新建客户档案
                    </option>
                    <option value="none">暂不关联</option>
                  </select>
                </td>
                <td
                  class="px-3 py-2 text-right tabular-nums whitespace-nowrap text-n-slate-12"
                >
                  {{ money(row.parsed?.amount, row.parsed?.currency) }}
                </td>
                <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
                  {{ row.parsed?.order_date || '—' }}
                </td>
                <td class="px-3 py-2 whitespace-nowrap">
                  <span v-if="row.orderNo" :class="goText">
                    已补建 {{ row.orderNo }}
                  </span>
                  <span
                    v-else-if="row.status === 'pending'"
                    class="text-n-slate-10"
                  >
                    等待识别
                  </span>
                  <span v-else-if="row.status === 'ok'" class="text-n-slate-11">
                    待补建
                  </span>
                  <span v-else class="text-n-ruby-11">{{ row.reason }}</span>
                </td>
                <td class="px-3 py-2 text-right">
                  <button
                    v-if="!row.orderNo"
                    type="button"
                    class="text-n-slate-9 hover:text-n-ruby-11"
                    @click="removeRow(row)"
                  >
                    <span class="i-lucide-x size-4" />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div v-if="loading" class="py-10 text-sm text-center text-n-slate-10">
        加载中…
      </div>

      <HScrollButtons v-if="!loading" />

      <div
        v-if="!loading"
        class="overflow-x-auto border rounded-xl border-n-weak"
      >
        <table class="w-full text-sm">
          <thead class="bg-n-alpha-1 text-n-slate-11">
            <tr>
              <th class="px-4 py-3 font-medium text-left">客户</th>
              <th class="px-4 py-3 font-medium text-left whitespace-nowrap">
                PI 文件
              </th>
              <th class="px-4 py-3 font-medium text-right whitespace-nowrap">
                大小
              </th>
              <th class="px-4 py-3 font-medium text-left whitespace-nowrap">
                该客户成交单
              </th>
              <th class="px-4 py-3 font-medium text-right whitespace-nowrap">
                操作
              </th>
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
