<script setup>
import { computed, ref, watch, onMounted, onBeforeUnmount } from 'vue';
import CustomersAPI from 'dashboard/api/crm/customers';
import { useAccount } from 'dashboard/composables/useAccount';
import ProductionOrdersAPI from 'dashboard/api/mes/productionOrders';
import RequestsAPI from 'dashboard/api/oa/approvalRequests';
import ChatAPI from 'dashboard/api/chat/conversations';
import VouchersAPI from 'dashboard/api/erp/vouchers';
import ShopsAPI from 'dashboard/api/tiktok/shops';
import TiktokTodayAPI from 'dashboard/api/tiktok/today';
import DocsAPI from 'dashboard/api/crm/knowledgeDocs';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const { accountScopedRoute } = useAccount();

const props = defineProps({
  kind: { type: String, required: true },
  compact: { type: Boolean, default: false },
  enabled: { type: Boolean, default: true },
  approverView: { type: Boolean, default: true },
  days: { type: Array, default: () => [] },
  userName: { type: String, default: '' },
});
const rows = ref([]);
const slideIndex = ref(0);
const paused = ref(false);
const previewDocs = import.meta.env.DEV ? [
  { id: 'preview-guide', title: '客户跟进工作指南', detail: '示例文档 · 操作手册', badge: '预览' },
  { id: 'preview-quality', title: '生产质量检查清单', detail: '示例文档 · 质量管理', badge: '预览' },
  { id: 'preview-project', title: '项目交付与验收模板', detail: '示例文档 · 项目协同', badge: '预览' },
] : [];
const slides = computed(() => props.kind === 'docs' ? [...rows.value, ...previewDocs] : rows.value);
const currentSlide = computed(() => slides.value[slideIndex.value % slides.value.length]);
let rotationTimer;
onMounted(() => {
  rotationTimer = setInterval(() => {
    if (!props.enabled || loading.value || error.value || paused.value || document.hidden || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    if (['crm', 'docs'].includes(props.kind) && slides.value.length > 1) slideIndex.value += 1;
  }, 4000);
});
onBeforeUnmount(() => clearInterval(rotationTimer));
const total = ref(null);
const tiktokToday = ref(null);
const loading = ref(false);
const error = ref('');
const statusLabels = { pending: '审批中', approved: '已通过', rejected: '已驳回', canceled: '已撤回' };
const captions = {
  crm: '我的最近客户', mes: '最近生产订单', team: '最近会话',
  erp: '最近凭证', tiktok: '可见店铺', docs: '最近更新的文档', hr: '我的本周考勤',
};
const caption = computed(() => props.kind === 'oa' ? (props.approverView ? '待我审批' : '我的申请') : captions[props.kind]);
const icons = { crm: 'i-lucide-user-round', mes: 'i-lucide-package', oa: 'i-lucide-clipboard-list', team: 'i-lucide-message-circle', erp: 'i-lucide-receipt-text', tiktok: 'i-lucide-store', docs: 'i-lucide-file-text', hr: 'i-lucide-calendar-check' };
const date = value => value ? new Date(value).toLocaleDateString('zh-CN', { month: '2-digit', day: '2-digit' }) : '';
const join = (...parts) => parts.filter(Boolean).join(' · ');
// Read-only previews reuse the same account-scoped, permission-checked APIs as each module.
watch(() => [props.kind, props.enabled, props.approverView], async (_, __, onCleanup) => {
  let active = true;
  onCleanup(() => { active = false; });
  rows.value = [];
  error.value = '';
  tiktokToday.value = null;
  if (!props.enabled || props.kind === 'hr') return;
  loading.value = true;
  try {
    let response;
    let map;
    switch (props.kind) {
      case 'crm':
        response = await CustomersAPI.get({ filter: 'mine', per_page: 3 });
        map = r => ({ id: r.id, title: r.name, detail: join(r.primary_contact_name, r.trade_country), badge: r.next_follow_up_at ? `${date(r.next_follow_up_at)} 跟进` : '' });
        break;
      case 'mes':
        response = await ProductionOrdersAPI.get({ page: 1, per_page: 3 });
        map = r => ({ id: r.id, title: r.order_no, detail: r.product_name, badge: r.qty == null ? '' : `${r.qty} ${r.unit || ''}` });
        break;
      case 'oa':
        response = await RequestsAPI.list({ filter: props.approverView ? 'todo' : 'mine', page: 1 });
        map = r => ({ id: r.id, title: r.title, detail: join(r.applicant_name, r.template_name), icon: r.template_icon || 'i-lucide-file-check', badge: statusLabels[r.status] || r.status });
        break;
      case 'team':
        response = await ChatAPI.list();
        map = r => ({ id: r.id, title: r.name, detail: r.last_message?.content || '暂无消息', badge: r.unread_count ? `${r.unread_count} 未读` : '', avatar: r.peer_avatar_url || r.avatar_url });
        break;
      case 'erp':
        response = await VouchersAPI.get({ page: 1, per_page: 3 });
        map = r => ({ id: r.id, title: r.voucher_no, detail: r.summary, badge: r.status_label });
        break;
      case 'tiktok':
        if (props.compact) {
          response = await TiktokTodayAPI.get();
          if (active) tiktokToday.value = response.data;
          return;
        }
        response = await ShopsAPI.get();
        map = r => ({ id: r.id, title: r.name, detail: join(r.department_name, r.region), badge: r.active ? '启用' : '停用' });
        break;
      case 'docs':
        response = await DocsAPI.get({ library: 'GENERAL', page: 1, per_page: 3 });
        map = r => ({ id: r.id, title: r.name, detail: r.category, badge: date(r.updated_at) });
        break;
      default: return;
    }
    if (active) {
      rows.value = response.data.payload.slice(0, 3).map(map);
      total.value = response.data.meta?.count ?? null;
    }
  } catch (e) {
    if (active) error.value = e.response?.status === 403 ? '暂无查看权限' : '暂时未能加载，进入模块查看';
  } finally {
    if (active) loading.value = false;
  }
}, { immediate: true });
</script>

<template>
  <div v-if="compact" class="mt-3 space-y-2 text-left" @mouseenter="paused = true" @mouseleave="paused = false" @focusin="paused = true" @focusout="paused = false">
    <div v-if="kind === 'docs'" class="flex h-full min-h-0 min-w-0 flex-col" :aria-busy="loading">
      <div class="relative -top-1 flex h-[30px] shrink-0 items-baseline gap-1.5">
        <span v-if="loading" class="block h-9 w-12 rounded-lg bg-[#edf0e8] motion-safe:animate-pulse" />
        <strong v-else class="text-[30px] font-semibold leading-none tabular-nums text-[#20241f]">{{ !enabled || error ? '—' : total ?? (rows.length ? '—' : 0) }}</strong>
        <div class="text-label-small text-[#8a9184]">文档总数</div>
      </div>
      <div class="mt-[10px] min-h-0 min-w-0 flex-1">
        <div v-if="loading" class="space-y-3" role="status" aria-label="正在加载文档">
          <div v-for="i in 2" :key="i" class="flex items-center gap-2 motion-safe:animate-pulse"><span class="size-8 shrink-0 rounded-lg bg-[#f0f2ed]" /><div class="flex-1 space-y-1.5"><span class="block h-2.5 w-3/4 rounded bg-[#edf0e8]" /><span class="block h-2 w-1/2 rounded bg-[#f3f4f0]" /></div></div>
        </div>
        <div v-else-if="!enabled || error || !rows.length" class="py-4 text-label-small text-[#92988c]" role="status">{{ !enabled ? '暂无查看权限' : error || '暂无文档，进入文档中心添加' }}</div>
        <div v-else class="relative h-full min-h-0 overflow-hidden">
          <Transition enter-active-class="transition-[opacity,transform] duration-200 ease-[cubic-bezier(0.23,1,0.32,1)] motion-reduce:transition-none" leave-active-class="transition-[opacity,transform] duration-200 ease-[cubic-bezier(0.23,1,0.32,1)] motion-reduce:transition-none" enter-from-class="translate-y-6 opacity-0 motion-reduce:translate-y-0" leave-to-class="-translate-y-6 opacity-0 motion-reduce:translate-y-0">
            <div :key="currentSlide.id" class="absolute inset-0 flex flex-col justify-evenly divide-y divide-black/5">
              <div v-for="offset in Math.min(3, slides.length)" :key="slides[(slideIndex + offset - 1) % slides.length].id" class="flex min-w-0 items-center gap-2 py-1">
                <span class="grid size-5 shrink-0 place-items-center text-[#80964e]"><Icon icon="i-lucide-file-text" class="size-4" /></span>
                <div class="min-w-0"><div class="truncate text-label-small text-[#30362c]" :title="slides[(slideIndex + offset - 1) % slides.length].title">{{ slides[(slideIndex + offset - 1) % slides.length].title }}</div></div>
              </div>
            </div>
          </Transition>
        </div>
      </div>
    </div>
    <div v-else-if="!enabled || error || loading || (kind !== 'tiktok' && !rows.length)" class="rounded-xl bg-[#f7f8f9] px-3 py-4 text-label-small text-[#8f8f8f]" role="status">{{ !enabled ? '暂无查看权限' : loading ? '加载中…' : error || '暂无记录' }}</div>
    <template v-else-if="kind === 'oa'">
      <div v-for="row in rows.slice(0, 2)" :key="row.id" class="flex min-h-[44px] min-w-0 items-center gap-[9px] rounded-[12px] border border-[#eceee7] bg-[#fafbf8] px-2 py-1">
        <span class="grid size-7 shrink-0 place-items-center rounded-lg bg-[#fdf1c6] text-[#a97e0c]"><Icon :icon="row.icon" class="size-4" /></span>
        <div class="min-w-0 flex-1"><div class="truncate text-label-small font-semibold text-[#20241f]" :title="row.title">{{ row.title }}</div><div class="mt-0.5 truncate text-label-small !text-[11px] text-[#929989]" :title="row.detail">{{ row.detail || row.badge }}</div></div>
        <Icon icon="i-lucide-chevron-right" class="size-3.5 shrink-0 text-[#929989]" />
      </div>
    </template>
    <template v-else-if="kind === 'tiktok'">
      <div class="text-label-small text-[#8a9184]">今日销售额</div>
      <div class="break-words text-3xl font-semibold tabular-nums text-[#20241f]">{{ tiktokToday?.summary?.amount_cny == null ? '—' : `¥${Number(tiktokToday.summary.amount_cny).toLocaleString('zh-CN', { maximumFractionDigits: 0 })}` }}</div>
      <div class="!mt-4 grid grid-cols-2 gap-3 border-t border-black/5 pt-3">
        <div><strong class="text-heading-1 tabular-nums">{{ tiktokToday?.summary?.total_orders ?? '—' }}</strong><div class="mt-1 text-label-small text-[#8a9184]">今日订单</div></div>
        <div><strong class="text-heading-1 tabular-nums">{{ tiktokToday?.summary?.total_units ?? '—' }}</strong><div class="mt-1 text-label-small text-[#8a9184]">售出台数</div></div>
      </div>
    </template>
    <template v-else>
      <div v-if="kind === 'team'" class="mb-3 flex -space-x-2">
        <span v-for="row in rows" :key="row.id" class="grid size-9 shrink-0 place-items-center overflow-hidden rounded-full border-2 border-white bg-[#edf0e8] text-label text-[#59654f]" :title="row.title"><img v-if="row.avatar" :src="row.avatar" alt="" class="h-full w-full object-cover" /><span v-else>{{ row.title?.slice(0, 1) }}</span></span>
      </div>
      <template v-if="kind !== 'team'">
      <div v-for="(row, i) in rows.slice(0, kind === 'oa' ? 2 : 1)" :key="row.id" class="flex items-center gap-3" :class="kind === 'team' ? 'border-t border-black/5 py-3' : 'rounded-xl border border-black/5 bg-[#fafbfc] px-3 py-3.5'">
        <span v-if="kind === 'team'" class="grid size-8 shrink-0 place-items-center overflow-hidden rounded-full bg-[#f0f3ec] text-label-small text-[#67715c]"><img v-if="row.avatar" :src="row.avatar" alt="" class="h-full w-full object-cover" /><Icon v-else icon="i-lucide-bell" class="size-4" /></span>
        <span v-else class="grid size-10 shrink-0 place-items-center rounded-xl border" :class="kind === 'oa' && i === 0 ? 'border-green-200 bg-green-50 text-green-600' : 'border-blue-100 bg-blue-50 text-blue-600'"><Icon :icon="kind === 'oa' ? 'i-lucide-file-text' : 'i-lucide-messages-square'" class="size-6" /></span>
        <div class="min-w-0 flex-1"><div class="truncate text-heading-3 text-[#20241f]" :title="row.title">{{ row.title }}</div><div class="mt-1 truncate text-label-small text-[#8a8e94]" :title="row.detail">{{ row.detail || row.badge }}</div></div>
        <Icon v-if="kind === 'oa'" icon="i-lucide-chevron-right" class="size-4 shrink-0 text-[#8a8e94]" />
        <span v-else-if="row.badge" class="shrink-0 rounded-full bg-emerald-50 px-2 py-1 text-label-small text-emerald-600">{{ row.badge }}</span>
      </div>
      </template>
    </template>
  </div>
  <div v-else class="wsh-art relative my-4 min-h-40 text-left motion-reduce:[&_*]:!animate-none" @mouseenter="paused = true" @mouseleave="paused = false" @focusin="paused = true" @focusout="paused = false">
    <div v-if="kind !== 'crm'" class="mb-2 flex items-center justify-between text-label-small text-[#878787]">
      <span>{{ caption }}</span>
      <Icon :icon="icons[kind]" class="size-3.5" aria-hidden="true" />
    </div>
    <div v-if="kind === 'hr'" class="rounded-2xl border border-[#e2e2e2] bg-white p-4">
      <div class="text-heading-3 text-[#323232]">{{ userName }}</div>
      <div v-if="!days.length" class="mt-4 text-label-small text-[#8f8f8f]">考勤数据加载中</div>
      <div v-else class="mt-4 grid grid-cols-7 gap-1">
        <div v-for="(day, i) in days" :key="i" class="flex flex-col items-center gap-2 text-label-small">
          <span class="text-[#909090]">{{ ['一', '二', '三', '四', '五', '六', '日'][i] }}</span>
          <span class="grid size-6 place-items-center rounded-full" :class="day.present ? 'bg-[#d8d8d8] text-[#616161]' : 'bg-[#f1f1f1] text-[#9b9b9b]'" :title="day.present ? '已出勤' : '无出勤记录'">
            <Icon :icon="day.present ? 'i-lucide-check' : 'i-lucide-minus'" class="size-3" />
          </span>
        </div>
      </div>
    </div>
    <div v-else-if="!enabled || error || loading || !rows.length" class="grid min-h-32 place-items-center rounded-2xl border border-dashed border-[#dadada] text-label-small text-[#8f8f8f]" role="status">
      {{ !enabled ? '暂无查看权限' : loading ? '正在加载真实记录…' : error || '暂无记录' }}
    </div>
    <div v-else-if="kind === 'crm'" class="relative h-full min-h-40 py-3">
      <div aria-hidden="true" class="absolute inset-x-2 inset-y-3 rotate-[7deg] rounded-[20px] bg-[#b9d57a]" />
      <div aria-hidden="true" class="absolute inset-x-2 inset-y-3 -rotate-[4deg] rounded-[20px] bg-[#eff6da]" />
      <Transition mode="out-in" enter-active-class="transition-[opacity,transform] duration-200 ease-[cubic-bezier(0.23,1,0.32,1)] motion-reduce:transition-none" leave-active-class="transition-opacity duration-150 motion-reduce:transition-none" enter-from-class="translate-y-2 opacity-0 motion-reduce:translate-y-0" leave-to-class="opacity-0">
      <router-link :key="currentSlide.id" :to="accountScopedRoute('crm_customer_detail_index', { id: currentSlide.id })" :aria-label="`查看客户 ${currentSlide.title}`" class="relative flex w-full h-full text-left text-[#242923] no-underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#7c9c42] min-h-36 flex-col justify-between rounded-[20px] bg-white p-4 shadow-sm">
        <div class="flex flex-col items-start gap-3">
          <span class="grid size-12 shrink-0 place-items-center rounded-full bg-[#eaf3ce] text-label text-[#30362b]">{{ currentSlide.title?.slice(0, 2) }}</span>
          <div class="min-w-0"><div class="line-clamp-2 text-heading-3 font-semibold text-[#242923]" :title="currentSlide.title">{{ currentSlide.title }}</div><div class="mt-1 truncate text-label-small text-[#949b8c]">{{ currentSlide.detail }}</div></div>
        </div>
        <div class="mt-4 flex items-center justify-between gap-2"><span class="rounded-lg border border-[#e4e9db] px-2 py-1 text-label-small text-[#77816a]">{{ currentSlide.badge || '查看客户' }}</span><span class="text-label-small text-[#a1aa91]">最近客户</span></div>
      </router-link>
      </Transition>
    </div>
    <div v-else-if="kind === 'mes'" class="relative h-48 overflow-hidden">
      <div aria-hidden="true" class="absolute inset-x-4 bottom-6 flex justify-between border-t border-dashed border-[#d6d6d6]"><span v-for="i in 3" :key="i" class="-mt-1 size-2 rounded-full bg-[#d6d6d6]" /></div>
      <div class="absolute inset-x-5 top-5 rounded-xl border border-[#dfdfdf] bg-white p-4 shadow-sm motion-safe:animate-wsh-travel">
        <div class="mb-3 flex items-center justify-between"><Icon icon="i-lucide-package" class="size-6 text-[#a8a8a8]" /><span class="rounded-md bg-[#eaeaea] px-2 py-1 text-label-small text-[#767676]">{{ rows[0].badge }}</span></div>
        <div class="truncate text-heading-3" :title="rows[0].title">{{ rows[0].title }}</div><div class="mt-1 line-clamp-2 text-label-small text-[#8a8a8a]">{{ rows[0].detail }}</div>
      </div>
      <span aria-hidden="true" class="absolute bottom-5 left-8 size-3 rounded-full bg-[#ababab] motion-safe:animate-wsh-route" />
    </div>
    <div v-else-if="kind === 'oa'" class="relative mx-3 mt-5 rounded-xl border border-[#dedede] bg-white px-3 pb-3 pt-5 shadow-sm motion-safe:animate-wsh-unfold">
      <span aria-hidden="true" class="absolute -top-2 left-1/2 h-4 w-14 -translate-x-1/2 rounded-md bg-[#dcdcdc]" />
      <div v-for="row in rows" :key="row.id" class="flex gap-2 border-b border-[#ededed] py-2 last:border-0">
        <Icon icon="i-lucide-file-clock" class="mt-1 size-4 shrink-0 text-[#a8a8a8]" />
        <div class="min-w-0 flex-1"><div class="truncate text-heading-3" :title="row.title">{{ row.title }}</div><div class="mt-1 truncate text-label-small text-[#929292]">{{ row.detail }}</div></div>
        <span class="self-start whitespace-nowrap rounded bg-[#f0f0f0] px-1 py-0.5 text-label-small text-[#8a8a8a]">{{ row.badge }}</span>
      </div>
    </div>
    <div v-else-if="kind === 'team'" class="space-y-3 py-3">
      <div v-for="(row, i) in rows.slice(0, 2)" :key="row.id" class="w-[88%] rounded-2xl border border-[#dedede] px-3 py-3 shadow-sm" :class="i === 0 ? 'rounded-bl-sm bg-white motion-safe:animate-wsh-message-one' : 'ml-auto rounded-br-sm bg-[#e9e9e9] motion-safe:animate-wsh-message-two'">
        <div class="flex items-center gap-2"><span class="size-5 rounded-full bg-[#c9c9c9] text-center text-label-small text-[#747474]">{{ row.title?.slice(0, 1) }}</span><span class="truncate text-heading-3">{{ row.title }}</span><span v-if="row.badge" class="ml-auto text-label-small text-[#888888]">{{ row.badge }}</span></div>
        <div class="mt-2 line-clamp-2 text-label-small text-[#888888]" :title="row.detail">{{ row.detail }}</div>
      </div>
    </div>
    <div v-else-if="kind === 'erp'" class="relative h-48 overflow-hidden">
      <div aria-hidden="true" class="absolute bottom-3 inset-x-4 h-8 rounded-lg bg-[#dedede]" />
      <div class="absolute inset-x-7 top-3 rounded-t-xl border border-[#dddddd] bg-white p-4 shadow-sm motion-safe:animate-wsh-unfold">
        <div class="flex items-center justify-between border-b border-dashed border-[#dedede] pb-3"><Icon icon="i-lucide-receipt-text" class="size-5 text-[#a2a2a2]" /><span class="text-label-small text-[#8b8b8b]">{{ rows[0].badge }}</span></div>
        <div class="mt-3 truncate text-heading-3" :title="rows[0].title">{{ rows[0].title }}</div><div class="mt-2 line-clamp-3 text-label-small text-[#929292]">{{ rows[0].detail }}</div>
        <div aria-hidden="true" class="mt-4 h-2 bg-[repeating-linear-gradient(90deg,#dadada_0px,#dadada_2px,transparent_2px,transparent_5px)]" />
      </div>
    </div>
    <div v-else-if="kind === 'docs'" class="relative h-48 pt-5 [perspective:800px]">
      <div aria-hidden="true" class="absolute bottom-2 inset-x-3 top-9 rounded-xl bg-[#dadada] before:absolute before:-top-3 before:left-0 before:h-5 before:w-20 before:rounded-t-xl before:bg-[#dadada]" />
      <div class="relative mx-6 rounded-t-xl border border-[#dddddd] bg-white px-3 py-2 shadow-sm motion-safe:animate-wsh-file">
        <div v-for="row in rows" :key="row.id" class="flex items-center gap-2 border-b border-[#eeeeee] py-2 text-label-small last:border-0"><Icon icon="i-lucide-file-text" class="size-4 shrink-0 text-[#9c9c9c]" /><span class="truncate" :title="row.title">{{ row.title }}</span></div>
      </div>
      <div aria-hidden="true" class="absolute inset-x-2 bottom-1 h-12 origin-bottom rounded-xl border border-[#d3d3d3] bg-[#e3e3e3] shadow-sm motion-safe:animate-wsh-folder" />
    </div>
    <div v-else-if="kind === 'tiktok'" class="relative mx-4 mt-4 overflow-hidden rounded-xl border border-[#dddddd] bg-white shadow-sm">
      <div aria-hidden="true" class="flex h-7 bg-[#d6d6d6]"><span v-for="i in 7" :key="i" class="flex-1 rounded-b-lg odd:bg-[#c4c4c4] even:bg-[#f1f1f1]" /></div>
      <div class="px-3 pb-3 pt-2">
        <div v-for="row in rows" :key="row.id" class="flex items-center gap-2 border-b border-[#ededed] py-2 last:border-0"><Icon icon="i-lucide-store" class="size-4 shrink-0 text-[#a0a0a0]" /><div class="min-w-0"><div class="truncate text-heading-3" :title="row.title">{{ row.title }}</div><div class="truncate text-label-small text-[#989898]">{{ row.detail }}</div></div><span class="ml-auto shrink-0 text-label-small text-[#989898]">{{ row.badge }}</span></div>
      </div>
    </div>
  </div>
</template>
