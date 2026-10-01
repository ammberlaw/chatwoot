<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import camelcaseKeys from 'camelcase-keys';
import QuoteRequestsAPI from 'dashboard/api/crm/quoteRequests';
import CrmAgentAPI from 'dashboard/api/crm/crmAgents';
import CustomerAPI from 'dashboard/api/crm/customers';
import { fmtYuan } from 'dashboard/helper/crmMoney';
// 平板电脑 / 商显工控的参数直接用 MES 那份定义（生产订单也是这一份），
// 保证「报价时问的参数」和「下单时填的参数」完全一致，那边加字段这边自动跟上。
import {
  SPEC_TEMPLATES,
  specFieldsFor,
  blankSpec,
} from 'dashboard/routes/dashboard/mes/pages/orderSpecFields';
import { isClassicTheme } from 'dashboard/components-next/CRM/charts/chartColors';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

// 定制报价：标准价目表里没有的定制件，业务员填参数交给主管定价。
// 与既有模块的分工——标准价目表是「查已发布的标准价」，报价单是「给客户的正式报价」，
// 这里补的是中间那一环：向上要个价。
const { accountId } = useAccount();
const currentUser = useMapGetter('getCurrentUser');
// 经典灰把 iris/blue 重定义成灰，主行动按钮在那儿会塌成灰；沿用全站约定换金黄。
const isClassic = ref(isClassicTheme());
const goColor = computed(() => (isClassic.value ? 'amber' : 'teal'));

const STATUS = {
  PENDING: { label: '待报价', class: 'bg-n-amber-3 text-n-amber-11' },
  QUOTED: { label: '已报价', class: 'bg-n-teal-3 text-n-teal-11' },
  CANCELLED: { label: '已撤销', class: 'bg-n-slate-4 text-n-slate-11' },
};
const CURRENCIES = ['USD', 'CNY', 'EUR'];
// 报价阶段问不着的规格项：这些是下生产单时才要确认的细节，现在问只会拖慢填表。
// 在这里过滤而不是改 MES 的定义——那份是生产订单在用的，不能动。
const HIDDEN_SPEC_KEYS = ['shipDate', 'manual', 'logoRemark', 'caseColors'];

const tab = ref('mine'); // mine | to_quote
const rows = ref([]);
const loading = ref(false);
const templates = ref([]);
const agents = ref([]);
const customers = ref([]);

// 管理员/副管另有「全部」——要能盯住有没有单子卡在某人手上没报。
const isAdminLike = computed(
  () =>
    currentUser.value?.role === 'administrator' ||
    currentUser.value?.crm_role === 'deputy_admin'
);
const tabs = computed(() => [
  { key: 'mine', label: '我的申请' },
  { key: 'to_quote', label: '待我报价' },
  { key: 'quoted_by_me', label: '我已报价' },
  ...(isAdminLike.value ? [{ key: 'all', label: '全部' }] : []),
]);

const load = async () => {
  loading.value = true;
  try {
    const { data } = await QuoteRequestsAPI.get({
      // 「全部」不传 filter，后端按可见范围返回（管理员=全部）。
      filter: tab.value === 'all' ? undefined : tab.value,
      per_page: 50,
    });
    rows.value = camelcaseKeys(data.payload || [], { deep: true });
  } catch (error) {
    useAlert(error?.response?.data?.error || '加载失败');
  } finally {
    loading.value = false;
  }
};

const setTab = key => {
  tab.value = key;
  load();
};

// ---- 提交申请 ----
const submitRef = ref(null);
const submitting = ref(false);
const form = ref({
  templateId: '',
  title: '',
  customerId: '',
  quantity: '',
});
const { isDirty, markPristine } = useDirtyGuard(() => form.value);
const fieldValues = ref({});
const pendingFiles = ref([]);
const fileInput = ref(null);

const activeTemplate = computed(() =>
  form.value.templateId.startsWith('tpl:')
    ? templates.value.find(t => String(t.id) === form.value.templateId.slice(4))
    : null
);
// 产品线选项：内置的平板电脑/商显工控（用 MES 规格）排在前，自建模板跟在后。
const templateOptions = computed(() => [
  ...Object.entries(SPEC_TEMPLATES).map(([key, v]) => ({
    value: `spec:${key}`,
    label: v.label,
  })),
  ...templates.value.map(t => ({
    value: `tpl:${t.id}`,
    label: `${t.productLine} · ${t.name}`,
  })),
]);

// 选中的是内置规格时返回规格 key，否则 null。
const activeSpec = computed(() =>
  form.value.templateId.startsWith('spec:')
    ? form.value.templateId.slice(5)
    : null
);
// 当前表单要渲染的字段：内置规格取 MES 定义，自建模板取模板配置。
const activeFields = computed(() => {
  const all = activeSpec.value
    ? specFieldsFor(activeSpec.value)
    : activeTemplate.value?.formFields || [];
  return all.filter(f => !HIDDEN_SPEC_KEYS.includes(f.key));
});
const hasCustomerField = computed(() =>
  activeFields.value.some(f => f.type === 'customer')
);
const customerOptions = computed(() => [
  { value: '', label: '不关联客户' },
  ...customers.value.map(c => ({ value: String(c.id), label: c.name })),
]);

const openSubmit = () => {
  form.value = {
    templateId: '',
    title: '',
    customerId: '',
    quantity: '',
  };
  fieldValues.value = {};
  pendingFiles.value = [];
  markPristine();
  submitRef.value?.open();
};

const onTemplateChange = () => {
  // 内置规格按 MES 的 blankSpec 预填（商显那套字段标准值就是「默认」两字，
  // 业务员只改要特殊处理的那几项，不用一个个敲）。
  fieldValues.value = activeSpec.value ? blankSpec(activeSpec.value) : {};
};

const toggleCheck = (key, opt) => {
  const cur = fieldValues.value[key] || [];
  fieldValues.value[key] = cur.includes(opt)
    ? cur.filter(v => v !== opt)
    : [...cur, opt];
};

const onPickFiles = event => {
  pendingFiles.value = [
    ...pendingFiles.value,
    ...Array.from(event.target.files || []),
  ];
  event.target.value = '';
};

const submitRequest = async () => {
  if (!form.value.templateId) {
    useAlert('请先选产品线');
    return;
  }
  const missing = activeFields.value.find(
    f =>
      !f.section && f.required && !String(fieldValues.value[f.key] ?? '').trim()
  );
  if (missing) {
    useAlert(`请填写「${missing.label}」`);
    return;
  }
  if (!form.value.title.trim()) {
    useAlert('请填写标题');
    return;
  }

  submitting.value = true;
  try {
    const fd = new FormData();
    if (activeSpec.value) {
      // 内置规格：没有数据库模板行，只传规格 key 和产品线名。
      fd.append('spec_template', activeSpec.value);
      fd.append('product_line', SPEC_TEMPLATES[activeSpec.value].label);
    } else {
      fd.append('template_id', form.value.templateId.slice(4));
    }
    fd.append('title', form.value.title.trim());
    fd.append('form_data', JSON.stringify(fieldValues.value));
    if (form.value.customerId)
      fd.append('crm_customer_id', form.value.customerId);
    if (form.value.quantity) fd.append('quantity', form.value.quantity);
    pendingFiles.value.forEach(f => fd.append('files[]', f));
    await QuoteRequestsAPI.submit(fd);
    submitRef.value?.close();
    useAlert('已提交，等待报价');
    load();
  } catch (error) {
    useAlert(error?.response?.data?.error || '提交失败，请稍后重试');
  } finally {
    submitting.value = false;
  }
};

// ---- 报价 ----
const quoteRef = ref(null);
const quoting = ref(false);
const activeRow = ref(null);
const quoteForm = ref({ price: '', currency: 'USD', validUntil: '', note: '' });
const { isDirty: isQuoteDirty, markPristine: markQuotePristine } =
  useDirtyGuard(() => quoteForm.value);

const openQuote = row => {
  activeRow.value = row;
  quoteForm.value = { price: '', currency: 'USD', validUntil: '', note: '' };
  markQuotePristine();
  quoteRef.value?.open();
};

const submitQuote = async () => {
  if (!String(quoteForm.value.price).trim()) {
    useAlert('请填写价格');
    return;
  }
  quoting.value = true;
  try {
    await QuoteRequestsAPI.quote(activeRow.value.id, {
      price: quoteForm.value.price,
      currency: quoteForm.value.currency,
      valid_until: quoteForm.value.validUntil || null,
      note: quoteForm.value.note,
    });
    quoteRef.value?.close();
    useAlert('已报价，业务员可以看到了');
    load();
  } catch (error) {
    useAlert(error?.response?.data?.error || '报价失败');
  } finally {
    quoting.value = false;
  }
};

// ---- 转交 ----
const transferRef = ref(null);
const transferring = ref(false);
const transferForm = ref({ toUserId: '', reason: '' });
const agentOptions = computed(() =>
  agents.value
    .filter(a => a.id !== currentUser.value?.id)
    .map(a => ({ value: String(a.id), label: a.name }))
);

const openTransfer = row => {
  activeRow.value = row;
  transferForm.value = { toUserId: '', reason: '' };
  transferRef.value?.open();
};

const submitTransfer = async () => {
  if (!transferForm.value.toUserId) {
    useAlert('请选择转交给谁');
    return;
  }
  transferring.value = true;
  try {
    await QuoteRequestsAPI.transfer(
      activeRow.value.id,
      transferForm.value.toUserId,
      transferForm.value.reason
    );
    transferRef.value?.close();
    useAlert('已转交');
    load();
  } catch (error) {
    useAlert(error?.response?.data?.error || '转交失败');
  } finally {
    transferring.value = false;
  }
};

const cancelRequest = async row => {
  try {
    await QuoteRequestsAPI.cancel(row.id);
    useAlert('已撤销');
    load();
  } catch (error) {
    useAlert(error?.response?.data?.error || '撤销失败');
  }
};

const emptyHint = computed(
  () =>
    ({
      mine: '还没有提交过定制报价申请',
      to_quote: '没有待你报价的单子',
      quoted_by_me: '你还没有报过价',
      all: '还没有任何定制报价申请',
    })[tab.value]
);

// ---- 详情 ----
// 列表摘要只铺前 8 项、还跳过「默认」值，够扫一眼但不够核对。点开看全套。
const detailRef = ref(null);
const detailRow = ref(null);

const openDetail = row => {
  detailRow.value = row;
  detailRef.value?.open();
};

// 详情里的完整规格：保留分组标题，「默认」值也照实显示（核对时要看得到）。
const detailFields = computed(() => {
  const row = detailRow.value;
  if (!row) return [];
  const all = row.specTemplate
    ? specFieldsFor(row.specTemplate)
    : row.formFields || [];
  return all.filter(f => !HIDDEN_SPEC_KEYS.includes(f.key));
});

const fieldText = (row, f) => {
  const v = row.formData?.[f.key];
  if (Array.isArray(v)) return v.length ? v.join('、') : '—';
  return String(v ?? '').trim() || '—';
};

const fmtPrice = row =>
  row.quotedPriceMicros == null
    ? '—'
    : `${row.quoteCurrency || ''} ${fmtYuan(row.quotedPriceMicros)}`;
const fmtDate = v => (v ? new Date(v).toLocaleDateString() : '—');
// 参数摘要：表单字段拼成一行，列表里一眼看清定制的是什么，不用点进去。
const paramSummary = row => {
  // 内置规格的字段定义在前端（MES 那份），自建模板的随接口带回来。
  const fields = row.specTemplate
    ? specFieldsFor(row.specTemplate)
    : row.formFields || [];
  return (
    fields
      .filter(f => !f.section)
      .map(f => {
        const v = row.formData?.[f.key];
        const text = Array.isArray(v) ? v.join('/') : v;
        // 商显那套字段标准值就是「默认」，列表里全列出来会刷屏，只显示改过的。
        return text && text !== '默认' ? `${f.label}：${text}` : null;
      })
      .filter(Boolean)
      .slice(0, 8)
      .join(' · ') || '—'
  );
};

onMounted(async () => {
  load();
  try {
    const [tpl, ag, cust] = await Promise.all([
      QuoteRequestsAPI.templates(),
      CrmAgentAPI.get(accountId.value, 'all'),
      CustomerAPI.get({ per_page: 200 }),
    ]);
    templates.value = camelcaseKeys(tpl.data.payload || [], { deep: true });
    agents.value = ag.data.payload || [];
    customers.value = camelcaseKeys(cust.data.payload || [], { deep: true });
  } catch {
    // 下拉数据取不到不阻断列表
  }
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div class="w-full px-4 py-4 mx-auto max-w-6xl sm:px-8 sm:py-6">
      <div class="flex flex-wrap items-center justify-between gap-3 mb-1">
        <h1 class="text-[22px] font-bold tracking-[-0.01em] text-n-slate-12">
          定制报价
        </h1>
        <Button
          label="发起定制报价"
          icon="i-lucide-plus"
          :color="goColor"
          size="sm"
          @click="openSubmit"
        />
      </div>
      <p class="mt-1 mb-5 text-sm text-n-slate-11">标准价目表里没有的定制件</p>

      <div class="flex items-center gap-1 mb-4">
        <button
          v-for="t in tabs"
          :key="t.key"
          type="button"
          class="px-3 py-1.5 text-sm rounded-lg"
          :class="
            tab === t.key
              ? 'bg-n-iris-9 text-white'
              : 'text-n-slate-11 hover:bg-n-alpha-1'
          "
          @click="setTab(t.key)"
        >
          {{ t.label }}
        </button>
      </div>

      <p v-if="loading" class="py-8 text-sm text-center text-n-slate-10">
        加载中…
      </p>
      <p
        v-else-if="!rows.length"
        class="py-10 text-sm text-center text-n-slate-10"
      >
        {{ emptyHint }}
      </p>

      <div v-else class="flex flex-col gap-3">
        <div
          v-for="row in rows"
          :key="row.id"
          class="p-4 transition border cursor-pointer rounded-2xl border-n-weak bg-n-solid-1/60 hover:border-n-slate-6 hover:bg-n-alpha-1"
          @click="openDetail(row)"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span class="font-mono text-sm font-semibold text-n-slate-12">
              {{ row.requestNo }}
            </span>
            <span
              class="px-2 py-[2px] text-[12px] font-medium rounded-full"
              :class="STATUS[row.status]?.class"
            >
              {{ STATUS[row.status]?.label || row.status }}
            </span>
            <span class="text-sm text-n-slate-12">{{ row.title }}</span>
            <span class="flex-1" />
            <span class="text-xs text-n-slate-10">
              {{ row.applicantName }} · {{ fmtDate(row.createdAt) }}
            </span>
          </div>

          <div class="mt-2 text-xs text-n-slate-11">
            {{ row.productLine }} · {{ paramSummary(row) }}
            <template v-if="row.quantity">· 数量 {{ row.quantity }}</template>
            <template v-if="row.customerName">
              · {{ row.customerName }}
            </template>
          </div>

          <div
            v-if="row.status === 'QUOTED'"
            class="flex flex-wrap items-center gap-3 p-3 mt-3 text-sm rounded-xl bg-n-alpha-1"
          >
            <span class="font-semibold text-n-slate-12">
              {{ fmtPrice(row) }}
            </span>
            <span v-if="row.validUntil" class="text-xs text-n-slate-11">
              有效期至 {{ fmtDate(row.validUntil) }}
            </span>
            <span class="text-xs text-n-slate-10">
              {{ row.quotedByName }} 于 {{ fmtDate(row.quotedAt) }} 报价
            </span>
            <span v-if="row.pricerNote" class="text-xs text-n-slate-11">
              · {{ row.pricerNote }}
            </span>
          </div>

          <div
            v-if="row.transfers?.length"
            class="mt-2 text-xs text-n-slate-10"
          >
            转交：{{
              row.transfers
                .map(
                  t =>
                    `${t.from || '系统'} → ${t.to}${t.reason ? `（${t.reason}）` : ''}`
                )
                .join('；')
            }}
          </div>

          <div class="flex flex-wrap items-center gap-2 mt-3">
            <span
              v-if="row.status === 'PENDING'"
              class="text-xs text-n-slate-10"
            >
              待 {{ row.pricerName || '（未指定报价人）' }} 报价
            </span>
            <span class="flex-1" />
            <Button
              v-if="
                row.status === 'PENDING' && row.pricerId === currentUser?.id
              "
              label="填写报价"
              size="sm"
              :color="goColor"
              @click.stop="openQuote(row)"
            />
            <Button
              v-if="
                row.status === 'PENDING' && row.pricerId === currentUser?.id
              "
              label="转交他人"
              size="sm"
              variant="outline"
              color="slate"
              @click.stop="openTransfer(row)"
            />
            <Button
              v-if="
                row.status === 'PENDING' && row.applicantId === currentUser?.id
              "
              label="撤销"
              size="sm"
              variant="outline"
              color="ruby"
              @click.stop="cancelRequest(row)"
            />
          </div>
        </div>
      </div>
    </div>

    <!-- 详情：列表摘要不够核对时点开看全套规格、附件、转交链路 -->
    <Dialog
      ref="detailRef"
      overflow-y-auto
      width="3xl"
      :title="detailRow ? detailRow.requestNo : ''"
      cancel-button-label="关闭"
      :show-confirm-button="false"
    >
      <div v-if="detailRow" class="flex flex-col gap-4">
        <div class="flex flex-wrap items-center gap-2">
          <span
            class="px-2 py-[2px] text-[12px] font-medium rounded-full"
            :class="STATUS[detailRow.status]?.class"
          >
            {{ STATUS[detailRow.status]?.label || detailRow.status }}
          </span>
          <span class="text-sm font-medium text-n-slate-12">
            {{ detailRow.title }}
          </span>
        </div>

        <div class="grid grid-cols-2 gap-y-1.5 gap-x-4 text-sm">
          <div class="text-n-slate-11">
            产品线
            <span class="ml-2 text-n-slate-12">{{
              detailRow.productLine
            }}</span>
          </div>
          <div class="text-n-slate-11">
            数量
            <span class="ml-2 text-n-slate-12">
              {{ detailRow.quantity || '—' }}
            </span>
          </div>
          <div class="text-n-slate-11">
            客户
            <span class="ml-2 text-n-slate-12">
              {{ detailRow.customerName || '未关联' }}
            </span>
          </div>
          <div class="text-n-slate-11">
            提交
            <span class="ml-2 text-n-slate-12">
              {{ detailRow.applicantName }} · {{ fmtDate(detailRow.createdAt) }}
            </span>
          </div>
        </div>

        <!-- 完整规格：按分组列，「默认」也照实显示，核对时要看得到 -->
        <div class="flex flex-col">
          <template v-for="(f, i) in detailFields" :key="f.key || `d${i}`">
            <div
              v-if="f.section"
              class="pt-3 mt-2 mb-1 text-sm font-medium border-t text-n-slate-12 border-n-weak"
            >
              {{ f.section }}
            </div>
            <div v-else class="flex gap-3 py-1 text-sm">
              <span class="w-28 shrink-0 text-n-slate-11">{{ f.label }}</span>
              <span class="text-n-slate-12">{{ fieldText(detailRow, f) }}</span>
            </div>
          </template>
        </div>

        <div v-if="detailRow.files?.length" class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">附件</span>
          <a
            v-for="f in detailRow.files"
            :key="f.id"
            :href="f.url"
            target="_blank"
            rel="noopener"
            class="text-sm text-n-iris-11 hover:underline"
          >
            {{ f.filename }}
          </a>
        </div>

        <div
          v-if="detailRow.transfers?.length"
          class="flex flex-col gap-1 p-3 rounded-xl bg-n-alpha-1"
        >
          <span class="text-sm font-medium text-n-slate-12">转交记录</span>
          <span
            v-for="(t, i) in detailRow.transfers"
            :key="i"
            class="text-xs text-n-slate-11"
          >
            {{ t.from || '系统' }} → {{ t.to }}
            <template v-if="t.reason">（{{ t.reason }}）</template>
            · {{ fmtDate(t.at) }}
          </span>
        </div>

        <div
          v-if="detailRow.status === 'QUOTED'"
          class="flex flex-col gap-1 p-3 rounded-xl bg-n-alpha-1"
        >
          <span class="text-base font-semibold text-n-slate-12">
            {{ fmtPrice(detailRow) }}
          </span>
          <span class="text-xs text-n-slate-11">
            有效期至 {{ fmtDate(detailRow.validUntil) }} ·
            {{ detailRow.quotedByName }} 于
            {{ fmtDate(detailRow.quotedAt) }} 报价
          </span>
          <span v-if="detailRow.pricerNote" class="text-xs text-n-slate-11">
            {{ detailRow.pricerNote }}
          </span>
        </div>
        <div v-else class="text-sm text-n-slate-10">
          待 {{ detailRow.pricerName || '（未指定报价人）' }} 报价
        </div>
      </div>
    </Dialog>

    <!-- 发起申请 -->
    <Dialog
      ref="submitRef"
      overflow-y-auto
      title="发起定制报价"
      description="按产品线选模板，参数填得越清楚，主管报价越快。"
      confirm-button-label="提交"
      :confirm-button-color="goColor"
      :is-loading="submitting"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="submitRequest"
      @close="markPristine"
      @save="submitRequest"
    >
      <div class="flex flex-col gap-3">
        <label class="flex flex-col gap-1">
          <span class="text-sm text-n-slate-11">产品线模板 *</span>
          <SelectCard
            v-model="form.templateId"
            :options="templateOptions"
            block
            @update:model-value="onTemplateChange"
          />
        </label>

        <label class="flex flex-col gap-1">
          <span class="text-sm text-n-slate-11">标题 *</span>
          <input
            v-model="form.title"
            type="text"
            placeholder="例：10.1寸定制 2000 台"
            class="w-full h-10 px-3 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
          />
        </label>

        <!-- 规格字段：内置的走 MES 定义（含分组标题/多选），自建模板走模板配置 -->
        <template v-for="(f, i) in activeFields" :key="f.key || `s${i}`">
          <!-- 分组标题：MES 规格里用 section 把字段分成「硬件规格」「定制项」等段 -->
          <div
            v-if="f.section"
            class="pt-2 mt-1 text-sm font-medium border-t text-n-slate-12 border-n-weak"
          >
            {{ f.section }}
          </div>
          <!-- 多选：LOGO 位置、网络制式这类可以多选 -->
          <div v-else-if="f.type === 'checks'" class="flex flex-col gap-1">
            <span class="text-sm text-n-slate-11">
              {{ f.label }}{{ f.required ? ' *' : '' }}
            </span>
            <div class="flex flex-wrap gap-3">
              <label
                v-for="opt in f.options || []"
                :key="opt"
                class="flex items-center gap-1.5 text-sm text-n-slate-11"
              >
                <input
                  type="checkbox"
                  class="reset-base size-4"
                  :checked="(fieldValues[f.key] || []).includes(opt)"
                  @change="toggleCheck(f.key, opt)"
                />
                {{ opt }}
              </label>
            </div>
          </div>
          <!-- MES 规格里的「客户」就是 type: customer，直接用客户选择器，
               不再在底下单列一个「关联客户」——同一件事问两遍。 -->
          <label v-else-if="f.type === 'customer'" class="flex flex-col gap-1">
            <span class="text-sm text-n-slate-11">{{ f.label }}</span>
            <SelectCard
              v-model="form.customerId"
              :options="customerOptions"
              block
            />
          </label>
          <label v-else class="flex flex-col gap-1">
            <span class="text-sm text-n-slate-11">
              {{ f.label }}{{ f.required ? ' *' : '' }}
            </span>
            <SelectCard
              v-if="f.type === 'select'"
              v-model="fieldValues[f.key]"
              :options="(f.options || []).map(o => ({ value: o, label: o }))"
              block
            />
            <textarea
              v-else-if="f.type === 'textarea'"
              v-model="fieldValues[f.key]"
              rows="3"
              class="w-full px-3 py-2 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
            />
            <DatePicker
              v-else-if="f.type === 'date'"
              :model-value="fieldValues[f.key]"
              block
              @update:model-value="v => (fieldValues[f.key] = v)"
            />
            <input
              v-else
              v-model="fieldValues[f.key]"
              :type="f.type === 'number' ? 'number' : 'text'"
              :placeholder="f.placeholder || ''"
              class="w-full h-10 px-3 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
            />
          </label>
        </template>

        <label class="flex flex-col gap-1">
          <span class="text-sm text-n-slate-11">数量</span>
          <input
            v-model="form.quantity"
            type="number"
            class="w-full h-10 px-3 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
          />
        </label>

        <!-- 规格里已有客户字段时不重复显示（自建模板才需要） -->
        <label v-if="!hasCustomerField" class="flex flex-col gap-1">
          <span class="text-sm text-n-slate-11">关联客户</span>
          <SelectCard
            v-model="form.customerId"
            :options="customerOptions"
            block
          />
        </label>

        <div class="flex flex-col gap-1">
          <span class="text-sm text-n-slate-11">附件（图纸 / 规格书）</span>
          <Button
            label="添加附件"
            icon="i-lucide-paperclip"
            variant="outline"
            color="slate"
            size="sm"
            @click="fileInput?.click()"
          />
          <input
            ref="fileInput"
            type="file"
            multiple
            class="hidden"
            @change="onPickFiles"
          />
          <span
            v-for="(f, i) in pendingFiles"
            :key="i"
            class="text-xs text-n-slate-11"
          >
            {{ f.name }}
          </span>
        </div>
      </div>
    </Dialog>

    <!-- 报价 -->
    <Dialog
      ref="quoteRef"
      title="填写报价"
      :description="
        activeRow ? `${activeRow.requestNo} · ${activeRow.title}` : ''
      "
      confirm-button-label="提交报价"
      :confirm-button-color="goColor"
      :is-loading="quoting"
      :dirty="isQuoteDirty"
      dirty-save-label="保存"
      @confirm="submitQuote"
      @close="markQuotePristine"
      @save="submitQuote"
    >
      <div class="flex flex-col gap-3">
        <div class="grid grid-cols-2 gap-3">
          <label class="flex flex-col gap-1">
            <span class="text-sm text-n-slate-11">价格 *</span>
            <input
              v-model="quoteForm.price"
              type="number"
              step="0.01"
              class="w-full h-10 px-3 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-sm text-n-slate-11">币种</span>
            <SelectCard
              v-model="quoteForm.currency"
              :options="CURRENCIES.map(c => ({ value: c, label: c }))"
              block
            />
          </label>
        </div>
        <label class="flex flex-col gap-1">
          <span class="text-sm text-n-slate-11">有效期至</span>
          <DatePicker
            :model-value="quoteForm.validUntil"
            block
            @update:model-value="v => (quoteForm.validUntil = v)"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-sm text-n-slate-11">说明（业务员可见）</span>
          <textarea
            v-model="quoteForm.note"
            rows="3"
            placeholder="例：含丝印，不含运费；数量低于 1000 台价格另议"
            class="w-full px-3 py-2 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
          />
        </label>
      </div>
    </Dialog>

    <!-- 转交 -->
    <Dialog
      ref="transferRef"
      title="转交他人报价"
      description="报不了价的单子可以推给别人，比如总经理。转交会留痕。"
      confirm-button-label="确认转交"
      confirm-button-color="iris"
      :is-loading="transferring"
      @confirm="submitTransfer"
    >
      <div class="flex flex-col gap-3">
        <label class="flex flex-col gap-1">
          <span class="text-sm text-n-slate-11">转交给 *</span>
          <SelectCard
            v-model="transferForm.toUserId"
            :options="agentOptions"
            block
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-sm text-n-slate-11">原因</span>
          <textarea
            v-model="transferForm.reason"
            rows="2"
            placeholder="例：定制件成本要总经理核"
            class="w-full px-3 py-2 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
          />
        </label>
      </div>
    </Dialog>
  </div>
</template>
