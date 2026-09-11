<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import AppSheet from '@/components/AppSheet.vue';
import FormField from '@/components/FormField.vue';
import {
  fetchCustomerDetail,
  createFollowUpNote,
  claimCustomer,
  releaseCustomer,
  reassignCustomers,
  attachCustomerFiles,
  detachCustomerFile,
  fetchCustomerAudits,
  fetchAgents,
} from '@/api/crm';
import { useCrmOptions } from '@/composables/useCrmOptions';
import {
  COUNTRY_LABELS,
  CUSTOMER_STATUS_LABELS,
  CUSTOMER_LEVEL_LABELS,
  PRODUCT_GROUP_LABELS,
  OPPORTUNITY_STAGE_LABELS,
  ORDER_STATUS_LABELS,
  FOLLOW_UP_METHOD_LABELS,
  FOLLOW_UP_RESULT_LABELS,
  toOptions,
} from '@/constants/crm';
import { money, shortDate, shortDateTime, fromNow, waLink } from '@/utils/format';

defineOptions({ name: 'CustomerDetailPage' });

const route = useRoute();
const router = useRouter();
const { ensureLoaded, groupLabel, sourceLabel } = useCrmOptions();

const customer = ref(null);
const detail = ref({});
const loading = ref(true);
const failed = ref(false);
const staleAt = ref(null);

// 分段：只在有数据的段之间切换，空段也保留入口（数量为 0 时用户也要知道）
const SECTIONS = [
  { key: 'notes', label: '跟进' },
  { key: 'opportunities', label: '商机' },
  { key: 'orders', label: '订单' },
  { key: 'pis', label: 'PI' },
  { key: 'production_orders', label: '生产' },
  { key: 'files', label: '文件' },
  { key: 'audits', label: '历史' },
];
const section = ref('notes');

const METHOD_OPTIONS = toOptions(FOLLOW_UP_METHOD_LABELS);
const RESULT_OPTIONS = toOptions(FOLLOW_UP_RESULT_LABELS);
// 文件挂在 customer 上而非 detail 顶层；历史另取接口，没数前不显数字
const countOf = key => {
  if (key === 'files') return customer.value?.files?.length || 0;
  if (key === 'audits') return audits.value.length;
  return detail.value[key]?.length || 0;
};

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const r = await fetchCustomerDetail(route.params.id);
    customer.value = r.data?.customer || null;
    detail.value = r.data || {};
    staleAt.value = r.fromCache ? r.at : null;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const countryLabel = computed(
  () => COUNTRY_LABELS[customer.value?.trade_country] || customer.value?.trade_country || '—'
);

// 「资料项」统一结构，模板里一次循环渲染，避免二十行重复 div
const profileRows = computed(() => {
  const c = customer.value || {};
  return [
    { label: '客户编号', value: c.customer_code },
    { label: '国家', value: countryLabel.value },
    { label: '城市', value: c.trade_city },
    { label: '客户等级', value: CUSTOMER_LEVEL_LABELS[c.customer_level] },
    { label: '客户分组', value: groupLabel(c.customer_group) },
    { label: '客户来源', value: sourceLabel(c.source_channel) },
    { label: '产品分组', value: PRODUCT_GROUP_LABELS[c.product_group] },
    { label: '负责人', value: c.account_owner_name },
    { label: '网址', value: c.website },
    { label: '地址', value: c.address },
    { label: '备注', value: c.customer_remark },
  ].filter(r => r.value);
});

const contactRows = computed(() => {
  const c = customer.value || {};
  return [
    { icon: 'i-lucide-mail', value: c.contact_email, href: `mailto:${c.contact_email}` },
    { icon: 'i-lucide-phone', value: c.contact_phone, href: `tel:${c.contact_phone}` },
    { icon: 'i-lucide-message-circle', value: c.whats_app, href: waLink(c.whats_app) },
    { icon: 'i-lucide-message-square', value: c.wechat, href: '' },
  ].filter(r => r.value);
});

// ── 归属操作（认领 / 转公海 / 分配）──
const audits = ref([]);
const agents = ref([]);
const acting = ref(false);
const actionError = ref('');
const ownerSheet = ref(false);
const uploading = ref(false);

const loadAudits = async () => {
  if (audits.value.length) return;
  try {
    const r = await fetchCustomerAudits(route.params.id);
    audits.value = r.data?.payload || [];
  } catch {
    audits.value = [];
  }
};

const openOwnerSheet = async () => {
  actionError.value = '';
  ownerSheet.value = true;
  if (agents.value.length) return;
  try {
    const r = await fetchAgents('all');
    agents.value = r.data?.payload || [];
  } catch {
    agents.value = [];
  }
};

// 三个归属动作共用一套「跑接口 → 重载 → 出错就把后端话原样透出」
const runAction = async fn => {
  acting.value = true;
  actionError.value = '';
  try {
    await fn();
    ownerSheet.value = false;
    await load();
  } catch (e) {
    actionError.value =
      e.response?.data?.message || e.response?.data?.error || '操作失败，请重试';
  } finally {
    acting.value = false;
  }
};

const claim = () => runAction(() => claimCustomer(route.params.id));
const release = () => runAction(() => releaseCustomer(route.params.id));
const assignTo = id =>
  runAction(() => reassignCustomers([Number(route.params.id)], id));

// ── 附件 ──
const fileInput = ref(null);
const onPickFiles = async event => {
  const picked = Array.from(event.target.files || []);
  event.target.value = '';
  if (!picked.length) return;
  uploading.value = true;
  actionError.value = '';
  try {
    await attachCustomerFiles(route.params.id, picked);
    await load();
  } catch {
    actionError.value = '附件上传失败，请重试';
  } finally {
    uploading.value = false;
  }
};

const removeFile = async fileId => {
  uploading.value = true;
  try {
    await detachCustomerFile(route.params.id, fileId);
    await load();
  } catch {
    actionError.value = '删除附件失败，请重试';
  } finally {
    uploading.value = false;
  }
};

const kb = size =>
  size >= 1048576 ? `${(size / 1048576).toFixed(1)} MB` : `${Math.round(size / 1024)} KB`;

// ── 记一笔跟进 ──
const noteOpen = ref(false);
const noteSaving = ref(false);
const noteError = ref('');
const note = ref({ follow_up_method: 'EMAIL', result_tag: '', text: '' });

const openNote = () => {
  note.value = { follow_up_method: 'EMAIL', result_tag: '', text: '' };
  noteError.value = '';
  noteOpen.value = true;
};

const saveNote = async () => {
  if (!note.value.text.trim()) {
    noteError.value = '请填写跟进内容';
    return;
  }
  noteSaving.value = true;
  noteError.value = '';
  try {
    // 后端 title 必填、body 选填；与网页端一致，正文写进 title
    await createFollowUpNote({
      title: note.value.text.trim(),
      follow_up_method: note.value.follow_up_method,
      result_tag: note.value.result_tag,
      crm_customer_id: Number(route.params.id),
    });
    noteOpen.value = false;
    section.value = 'notes';
    await load();
  } catch (e) {
    noteError.value = e.response?.data?.message || '保存失败，请重试';
  } finally {
    noteSaving.value = false;
  }
};

onMounted(() => {
  ensureLoaded();
  load();
});
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader back :title="customer?.name || '客户'" :subtitle="customer ? countryLabel : ''">
      <template #actions>
        <button
          type="button"
          aria-label="归属操作"
          class="grid rounded-full size-9 place-items-center text-n-slate-11 active:bg-n-alpha-1"
          @click="openOwnerSheet"
        >
          <span class="size-5 i-lucide-user-cog" />
        </button>
        <button
          type="button"
          aria-label="编辑客户"
          class="grid rounded-full size-9 place-items-center text-n-iris-11 active:bg-n-alpha-1"
          @click="router.push({ name: 'customer-edit', params: { id: route.params.id } })"
        >
          <span class="size-5 i-lucide-pencil" />
        </button>
      </template>
    </PageHeader>

    <div class="flex-1 min-h-0 px-4 pt-3 overflow-y-auto">
      <DataState
        :loading="loading"
        :failed="failed"
        :empty="!customer"
        :stale-at="staleAt"
        empty-text="客户不存在或无权查看"
        @retry="load"
      >
        <!-- 概要 -->
        <div class="grid grid-cols-3 p-3 wt-card">
          <div class="text-center">
            <div class="text-lg font-bold text-n-slate-12">
              {{ money(customer.deal_total_amount_micros) }}
            </div>
            <div class="mt-0.5 text-xs text-n-slate-10">累计成交</div>
          </div>
          <div class="text-center border-x border-n-weak">
            <div class="text-lg font-bold text-n-slate-12">
              {{ customer.deal_order_count || 0 }}
            </div>
            <div class="mt-0.5 text-xs text-n-slate-10">成交订单</div>
          </div>
          <div class="text-center">
            <div class="text-lg font-bold text-n-slate-12">
              {{ fromNow(customer.last_touch_at) }}
            </div>
            <div class="mt-0.5 text-xs text-n-slate-10">最近联系</div>
          </div>
        </div>

        <div class="flex flex-wrap gap-2 mt-3">
          <span
            v-if="CUSTOMER_STATUS_LABELS[customer.customer_status]"
            class="px-2 py-1 text-xs rounded-lg bg-n-iris-3 text-n-iris-11"
          >
            {{ CUSTOMER_STATUS_LABELS[customer.customer_status] }}
          </span>
          <span
            v-if="customer.is_in_public_pool"
            class="px-2 py-1 text-xs rounded-lg bg-n-amber-3 text-n-amber-11"
          >
            公海
          </span>
          <span
            v-if="customer.next_follow_up_at"
            class="px-2 py-1 text-xs rounded-lg bg-n-alpha-1 text-n-slate-11"
          >
            下次跟进 {{ shortDate(customer.next_follow_up_at) }}
          </span>
        </div>

        <!-- AI 下一步建议：收信时已生成好缓存，这里直接读 -->
        <div v-if="customer.ai_next_step" class="p-3 mt-3 wt-card">
          <div class="flex items-center gap-1.5 text-xs font-medium text-n-iris-11">
            <span class="size-3.5 i-lucide-sparkles" />
            下一步建议
          </div>
          <p class="mt-1.5 text-sm leading-relaxed whitespace-pre-line text-n-slate-11">
            {{ customer.ai_next_step }}
          </p>
        </div>

        <!-- 联系方式 -->
        <div v-if="contactRows.length" class="mt-3 overflow-hidden wt-card">
          <div v-if="customer.primary_contact_name" class="px-3 py-2.5 border-b border-n-weak">
            <span class="text-sm font-medium text-n-slate-12">
              {{ customer.primary_contact_name }}
            </span>
            <span v-if="customer.contact_job_title" class="ml-2 text-xs text-n-slate-10">
              {{ customer.contact_job_title }}
            </span>
          </div>
          <component
            :is="row.href ? 'a' : 'div'"
            v-for="row in contactRows"
            :key="row.icon"
            :href="row.href || undefined"
            class="flex items-center gap-3 px-3 py-2.5 border-b last:border-b-0 border-n-weak"
            :class="row.href ? 'active:bg-n-alpha-1' : ''"
          >
            <span class="flex-none size-4 text-n-slate-10" :class="row.icon" />
            <span
              class="flex-1 text-sm truncate"
              :class="row.href ? 'text-n-iris-11' : 'text-n-slate-12'"
            >
              {{ row.value }}
            </span>
          </component>
        </div>

        <!-- 分段 -->
        <div class="flex gap-2 mt-4 -mx-4 px-4 overflow-x-auto [&::-webkit-scrollbar]:hidden">
          <button
            v-for="s in SECTIONS"
            :key="s.key"
            type="button"
            class="flex-none h-8 px-3 text-sm leading-none rounded-full"
            :class="
              section === s.key
                ? 'bg-n-iris-9 text-white font-medium'
                : 'bg-n-alpha-1 text-n-slate-11'
            "
            @click="section = s.key; s.key === 'audits' && loadAudits()"
          >
            {{ s.label }}{{ countOf(s.key) ? ` ${countOf(s.key)}` : '' }}
          </button>
        </div>

        <div class="mt-3">
          <!-- 跟进记录 -->
          <template v-if="section === 'notes'">
            <button type="button" class="w-full mb-2 wt-btn-ghost" @click="openNote">
              <span class="mr-1.5 size-4 i-lucide-plus" />
              记一笔跟进
            </button>
            <p v-if="!detail.notes?.length" class="py-8 text-sm text-center text-n-slate-11">
              还没有跟进记录
            </p>
            <ul v-else class="flex flex-col gap-2">
              <li v-for="n in detail.notes" :key="n.id" class="p-3 wt-card">
                <div class="flex items-center gap-2 text-xs text-n-slate-10">
                  <span v-if="n.follow_up_method" class="text-n-iris-11">
                    {{ FOLLOW_UP_METHOD_LABELS[n.follow_up_method] || n.follow_up_method }}
                  </span>
                  <span v-if="n.result_tag">
                    {{ FOLLOW_UP_RESULT_LABELS[n.result_tag] || n.result_tag }}
                  </span>
                  <span class="ml-auto">{{ fromNow(n.created_at) }}</span>
                </div>
                <p class="mt-1.5 text-sm leading-relaxed whitespace-pre-line text-n-slate-12">
                  {{ n.title }}
                </p>
                <p
                  v-if="n.body"
                  class="mt-1 text-sm leading-relaxed whitespace-pre-line text-n-slate-11"
                >
                  {{ n.body }}
                </p>
                <p v-if="n.owner_name" class="mt-1.5 text-xs text-n-slate-10">
                  {{ n.owner_name }}
                </p>
              </li>
            </ul>
          </template>

          <!-- 商机 -->
          <template v-else-if="section === 'opportunities'">
            <p
              v-if="!detail.opportunities?.length"
              class="py-8 text-sm text-center text-n-slate-11"
            >
              暂无商机
            </p>
            <ul v-else class="flex flex-col gap-2">
              <li v-for="o in detail.opportunities" :key="o.id" class="p-3 wt-card">
                <div class="flex items-start gap-3">
                  <div class="flex-1 min-w-0">
                    <div class="text-sm font-medium truncate text-n-slate-12">{{ o.name }}</div>
                    <div class="mt-0.5 text-xs text-n-slate-10">
                      {{ OPPORTUNITY_STAGE_LABELS[o.sales_stage] || o.sales_stage }}
                      <template v-if="o.expected_close_date">
                        · 预计 {{ shortDate(o.expected_close_date) }}
                      </template>
                    </div>
                  </div>
                  <div class="flex-none text-sm font-semibold text-n-slate-12">
                    {{ money(o.amount_micros, o.currency) }}
                  </div>
                </div>
              </li>
            </ul>
          </template>

          <!-- 订单 -->
          <template v-else-if="section === 'orders'">
            <p v-if="!detail.orders?.length" class="py-8 text-sm text-center text-n-slate-11">
              暂无订单
            </p>
            <ul v-else class="flex flex-col gap-2">
              <li v-for="o in detail.orders" :key="o.id" class="p-3 wt-card">
                <div class="flex items-start gap-3">
                  <div class="flex-1 min-w-0">
                    <div class="text-sm font-medium truncate text-n-slate-12">
                      {{ o.order_no || o.name }}
                    </div>
                    <div class="mt-0.5 text-xs text-n-slate-10">
                      {{ ORDER_STATUS_LABELS[o.status] || o.status }}
                      <template v-if="o.order_date"> · {{ shortDate(o.order_date) }}</template>
                    </div>
                  </div>
                  <div class="flex-none text-sm font-semibold text-n-slate-12">
                    {{ money(o.order_amount_micros, o.order_currency) }}
                  </div>
                </div>
              </li>
            </ul>
          </template>

          <!-- PI -->
          <template v-else-if="section === 'pis'">
            <p v-if="!detail.pis?.length" class="py-8 text-sm text-center text-n-slate-11">
              暂无 PI
            </p>
            <ul v-else class="flex flex-col gap-2">
              <li v-for="p in detail.pis" :key="p.id" class="p-3 wt-card">
                <div class="flex items-start gap-3">
                  <div class="flex-1 min-w-0">
                    <div class="text-sm font-medium truncate text-n-slate-12">{{ p.pi_no }}</div>
                    <div class="mt-0.5 text-xs text-n-slate-10">
                      {{ p.status }}
                      <template v-if="p.pi_date"> · {{ shortDate(p.pi_date) }}</template>
                    </div>
                  </div>
                  <div class="flex-none text-sm font-semibold text-n-slate-12">
                    {{ money(p.total_amount_micros, p.currency) }}
                  </div>
                </div>
              </li>
            </ul>
          </template>

          <!-- 生产订单：销售端只看阶段名，不涉及成本 -->
          <template v-else-if="section === 'production_orders'">
            <p
              v-if="!detail.production_orders?.length"
              class="py-8 text-sm text-center text-n-slate-11"
            >
              暂无生产订单
            </p>
            <ul v-else class="flex flex-col gap-2">
              <li v-for="p in detail.production_orders" :key="p.id" class="p-3 wt-card">
                <div class="flex items-start gap-3">
                  <div class="flex-1 min-w-0">
                    <div class="text-sm font-medium truncate text-n-slate-12">
                      {{ p.product_name }}
                    </div>
                    <div class="mt-0.5 text-xs text-n-slate-10">
                      {{ p.order_no }}
                      <template v-if="p.stage"> · {{ p.stage }}</template>
                      <template v-if="p.delivery_date">
                        · 交期 {{ shortDate(p.delivery_date) }}
                      </template>
                    </div>
                  </div>
                  <div class="flex-none text-sm font-semibold text-n-slate-12">
                    {{ p.produced_qty || 0 }}/{{ p.qty }}{{ p.unit }}
                  </div>
                </div>
              </li>
            </ul>
          </template>

          <!-- 文件 -->
          <template v-else-if="section === 'files'">
            <input ref="fileInput" type="file" multiple class="hidden" @change="onPickFiles" />
            <button
              type="button"
              class="w-full mb-2 wt-btn-ghost"
              :disabled="uploading"
              @click="fileInput.click()"
            >
              <span class="mr-1.5 size-4 i-lucide-plus" />
              {{ uploading ? '处理中…' : '上传附件' }}
            </button>
            <p v-if="!customer.files?.length" class="py-8 text-sm text-center text-n-slate-11">
              还没有附件
            </p>
            <ul v-else class="flex flex-col gap-2">
              <li v-for="f in customer.files" :key="f.id" class="flex items-center gap-3 p-3 wt-card">
                <span class="flex-none size-4 text-n-slate-10 i-lucide-paperclip" />
                <a
                  :href="f.url"
                  target="_blank"
                  rel="noopener"
                  class="flex-1 text-sm truncate text-n-iris-11"
                >
                  {{ f.filename }}
                </a>
                <span class="flex-none text-xs text-n-slate-10">{{ kb(f.byte_size) }}</span>
                <button
                  type="button"
                  :aria-label="`删除 ${f.filename}`"
                  class="grid flex-none rounded-full size-7 place-items-center text-n-slate-10 active:bg-n-alpha-1"
                  :disabled="uploading"
                  @click="removeFile(f.id)"
                >
                  <span class="size-4 i-lucide-trash-2" />
                </button>
              </li>
            </ul>
          </template>

          <!-- 操作历史 -->
          <template v-else-if="section === 'audits'">
            <p v-if="!audits.length" class="py-8 text-sm text-center text-n-slate-11">
              暂无操作记录
            </p>
            <ul v-else class="overflow-hidden wt-card">
              <li
                v-for="a in audits"
                :key="a.id"
                class="px-3 py-2.5 border-b last:border-b-0 border-n-weak"
              >
                <div class="flex items-baseline gap-2">
                  <span class="text-sm text-n-slate-12">{{ a.user_name }}</span>
                  <span class="ml-auto text-xs text-n-slate-10">
                    {{ shortDateTime(a.created_at) }}
                  </span>
                </div>
                <p class="mt-0.5 text-xs text-n-slate-11">
                  {{ a.action === 'create' ? '建档' : '修改' }}
                  <template v-if="a.changed_fields?.length">
                    · {{ a.changed_fields.join('、') }}
                  </template>
                </p>
              </li>
            </ul>
          </template>
        </div>

        <p v-if="actionError" class="mt-3 text-sm text-n-ruby-11">{{ actionError }}</p>

        <!-- 资料 -->
        <div v-if="profileRows.length" class="mt-4 overflow-hidden wt-card">
          <div
            v-for="row in profileRows"
            :key="row.label"
            class="flex items-start gap-3 px-3 py-2.5 border-b last:border-b-0 border-n-weak"
          >
            <span class="flex-none w-20 text-xs text-n-slate-10">{{ row.label }}</span>
            <span class="flex-1 text-sm break-words text-n-slate-12">{{ row.value }}</span>
          </div>
        </div>

        <div class="h-6" />
      </DataState>
    </div>

    <AppSheet :open="ownerSheet" title="客户归属" @close="ownerSheet = false">
      <p class="text-sm text-n-slate-11">
        当前负责人：{{ customer?.account_owner_name || '未分配' }}
        <template v-if="customer?.is_in_public_pool"> · 在公海</template>
      </p>

      <div class="flex flex-col gap-2 mt-4">
        <button
          v-if="customer?.is_in_public_pool"
          type="button"
          class="w-full wt-btn-primary"
          :disabled="acting"
          @click="claim"
        >
          认领到我名下
        </button>
        <button
          v-else
          type="button"
          class="w-full wt-btn text-n-amber-11 bg-n-amber-3 active:bg-n-amber-4"
          :disabled="acting"
          @click="release"
        >
          转入公海
        </button>
      </div>

      <template v-if="!customer?.is_in_public_pool">
        <h3 class="mt-5 mb-2 text-xs font-semibold tracking-wide text-n-slate-10">
          分配给其他成员
        </h3>
        <p v-if="!agents.length" class="text-sm text-n-slate-11">成员列表加载中…</p>
        <ul v-else class="overflow-hidden wt-card">
          <li v-for="a in agents" :key="a.id">
            <button
              type="button"
              class="w-full px-3 py-2.5 text-sm text-left border-b last:border-b-0 border-n-weak text-n-slate-12 active:bg-n-alpha-1 disabled:opacity-40"
              :disabled="acting || a.id === customer?.account_owner_id"
              @click="assignTo(a.id)"
            >
              {{ a.name }}
              <span v-if="a.id === customer?.account_owner_id" class="text-xs text-n-slate-10">
                （当前）
              </span>
            </button>
          </li>
        </ul>
      </template>

      <p v-if="actionError" class="mt-3 text-sm text-n-ruby-11">{{ actionError }}</p>
    </AppSheet>

    <AppSheet :open="noteOpen" title="记一笔跟进" @close="noteOpen = false">
      <div class="flex flex-col gap-4">
        <FormField label="跟进方式">
          <select v-model="note.follow_up_method" class="wt-field">
            <option v-for="o in METHOD_OPTIONS" :key="o.value" :value="o.value">
              {{ o.label }}
            </option>
          </select>
        </FormField>
        <FormField label="跟进结果">
          <select v-model="note.result_tag" class="wt-field">
            <option value="">不标记</option>
            <option v-for="o in RESULT_OPTIONS" :key="o.value" :value="o.value">
              {{ o.label }}
            </option>
          </select>
        </FormField>
        <FormField label="跟进内容" required>
          <textarea
            v-model="note.text"
            rows="5"
            placeholder="聊了什么、客户什么反馈、下一步做什么"
            class="wt-field"
          />
        </FormField>
        <p v-if="noteError" class="text-sm text-n-ruby-11">{{ noteError }}</p>
      </div>
      <template #footer>
        <button
          type="button"
          class="w-full wt-btn-primary"
          :disabled="noteSaving"
          @click="saveNote"
        >
          {{ noteSaving ? '保存中…' : '保存' }}
        </button>
      </template>
    </AppSheet>
  </div>
</template>
