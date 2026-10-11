<script setup>
import { computed, onMounted, ref } from 'vue';
import camelcaseKeys from 'camelcase-keys';
import { useAlert } from 'dashboard/composables';
import { useCrmExhibitionsStore } from 'dashboard/stores/crm/exhibitions';
import CrmExhibitionAPI from 'dashboard/api/crm/exhibitions';
import CrmExhibitionInviteAPI from 'dashboard/api/crm/exhibitionInvites';
import { COUNTRY_LABELS } from 'dashboard/routes/dashboard/crm/constants/countries';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';

const store = useCrmExhibitionsStore();

const countryOptions = [
  { value: '', label: '不限国家' },
  ...Object.entries(COUNTRY_LABELS).map(([value, label]) => ({ value, label })),
];
const REGION_LABELS = {
  NORTH_AMERICA: '北美',
  EUROPE: '欧洲',
  SOUTH_AMERICA: '南美',
  MIDDLE_EAST: '中东',
  SOUTHEAST_ASIA: '东南亚',
  AFRICA: '非洲',
  OTHER: '其他',
};
const regionOptions = [
  { value: '', label: '不限地区' },
  ...Object.entries(REGION_LABELS).map(([value, label]) => ({ value, label })),
];
const countryLabel = c => COUNTRY_LABELS[c] || c || '';
const regionLabel = r => REGION_LABELS[r] || r || '';

const STAGE_META = {
  pending: { label: '待邀约', cls: 'bg-n-alpha-2 text-n-slate-11' },
  invited: { label: '已邀约', cls: 'bg-n-blue-3 text-n-blue-11' },
  interacted: { label: '已互动', cls: 'bg-n-iris-3 text-n-iris-11' },
  accepted: { label: '已接受', cls: 'bg-n-teal-3 text-n-teal-11' },
  declined: { label: '谢绝', cls: 'bg-n-ruby-3 text-n-ruby-11' },
};
const MATCH_META = {
  high: { label: '高匹配', cls: 'bg-n-teal-3 text-n-teal-11' },
  mid: { label: '中匹配', cls: 'bg-n-amber-3 text-n-amber-11' },
  low: { label: '低匹配', cls: 'bg-n-alpha-2 text-n-slate-11' },
};

const records = computed(() => store.getRecords);
const fetching = computed(() => store.getUIFlags.fetchingList);

const selectedId = ref(null);
const detail = ref(null);
const detailLoading = ref(false);

const loadList = () => store.get();

const openDetail = async id => {
  selectedId.value = id;
  detailLoading.value = true;
  try {
    const { data } = await CrmExhibitionAPI.show(id);
    detail.value = camelcaseKeys(data, { deep: true });
  } catch {
    useAlert('加载展会详情失败');
  } finally {
    detailLoading.value = false;
  }
};

const refreshBoth = async () => {
  await loadList();
  if (selectedId.value) await openDetail(selectedId.value);
};

// ── 展会新建/编辑 ──────────────────────────────────────────
const exDialog = ref(null);
const editingId = ref(null);
const form = ref({});
const blankForm = () => ({
  name: '',
  country: '',
  region: '',
  city: '',
  venue: '',
  hall: '',
  boothNo: '',
  website: '',
  startsOn: '',
  endsOn: '',
  featuredProducts: '',
});
const saving = computed(
  () => store.getUIFlags.creatingItem || store.getUIFlags.updatingItem
);
const formInvalid = computed(() => !form.value.name || !form.value.name.trim());

const openCreate = () => {
  editingId.value = null;
  form.value = blankForm();
  exDialog.value?.open();
};
const openEdit = () => {
  const d = detail.value;
  editingId.value = d.id;
  form.value = {
    name: d.name || '',
    country: d.country || '',
    region: d.region || '',
    city: d.city || '',
    venue: d.venue || '',
    hall: d.hall || '',
    boothNo: d.boothNo || '',
    website: d.website || '',
    startsOn: d.startsOn ? d.startsOn.slice(0, 10) : '',
    endsOn: d.endsOn ? d.endsOn.slice(0, 10) : '',
    featuredProducts: d.featuredProducts || '',
  };
  exDialog.value?.open();
};

const saveExhibition = async () => {
  if (formInvalid.value) return;
  const payload = { ...form.value, name: form.value.name.trim() };
  try {
    if (editingId.value) {
      await store.update({ id: editingId.value, ...payload });
      await openDetail(editingId.value);
    } else {
      const rec = await store.create(payload);
      if (rec?.id) await openDetail(rec.id);
    }
    exDialog.value?.close();
    useAlert(editingId.value ? '展会已更新' : '展会已创建');
  } catch {
    useAlert('保存失败');
  }
};

const deleteExhibition = async () => {
  const d = detail.value;
  // eslint-disable-next-line no-alert
  if (!window.confirm(`确认删除展会「${d.name}」及其邀约名单？`)) return;
  await store.delete(d.id);
  detail.value = null;
  selectedId.value = null;
  useAlert('展会已删除');
};

// ── 匹配潜客 → 加入名单 ────────────────────────────────────
const candDialog = ref(null);
const candidates = ref([]);
const candLoading = ref(false);
const includeLow = ref(false);
const selectedCand = ref(new Set());
const adding = ref(false);

const loadCandidates = async () => {
  candLoading.value = true;
  try {
    const { data } = await CrmExhibitionAPI.candidates(selectedId.value, {
      include_low: includeLow.value,
    });
    candidates.value = camelcaseKeys(data.payload || [], { deep: true });
  } catch {
    useAlert('匹配潜客失败');
  } finally {
    candLoading.value = false;
  }
};
const openCandidates = async () => {
  selectedCand.value = new Set();
  candDialog.value?.open();
  await loadCandidates();
};
const toggleCand = id => {
  const s = new Set(selectedCand.value);
  if (s.has(id)) s.delete(id);
  else s.add(id);
  selectedCand.value = s;
};
const toggleAllCand = () => {
  if (selectedCand.value.size === candidates.value.length) {
    selectedCand.value = new Set();
  } else {
    selectedCand.value = new Set(candidates.value.map(c => c.id));
  }
};
const addSelected = async () => {
  const ids = [...selectedCand.value];
  if (!ids.length) {
    useAlert('请先勾选客户');
    return;
  }
  adding.value = true;
  try {
    const { data } = await CrmExhibitionAPI.addInvites(selectedId.value, ids);
    detail.value = camelcaseKeys(data, { deep: true });
    await loadList();
    candDialog.value?.close();
    useAlert(`已加入 ${ids.length} 个客户到邀约名单`);
  } catch {
    useAlert('加入名单失败');
  } finally {
    adding.value = false;
  }
};

// ── 从 Apollo 找新买家（突破自有客户池）────────────────────
// 展会国家码 → 英文国名（Apollo 用英文过滤）；缺的回落原值，用户可改。
const COUNTRY_EN = {
  USA: 'United States',
  GERMANY: 'Germany',
  UK: 'United Kingdom',
  FRANCE: 'France',
  ITALY: 'Italy',
  SPAIN: 'Spain',
  CANADA: 'Canada',
  AUSTRALIA: 'Australia',
  CHINA: 'China',
  JAPAN: 'Japan',
  SOUTH_KOREA: 'South Korea',
  INDIA: 'India',
  RUSSIA: 'Russia',
  BRAZIL: 'Brazil',
  MEXICO: 'Mexico',
  NETHERLANDS: 'Netherlands',
  BELGIUM: 'Belgium',
  SWITZERLAND: 'Switzerland',
  SWEDEN: 'Sweden',
  NORWAY: 'Norway',
  DENMARK: 'Denmark',
  FINLAND: 'Finland',
  AUSTRIA: 'Austria',
  POLAND: 'Poland',
  CZECH: 'Czechia',
  TURKEY: 'Turkey',
  UAE: 'United Arab Emirates',
};
const apolloDialog = ref(null);
const apolloCountry = ref('');
const apolloKeywords = ref('');
const apolloResults = ref([]);
const apolloLoading = ref(false);
const apolloSearched = ref(false);
const selectedApollo = ref(new Set());
const apolloAdding = ref(false);

const openApollo = () => {
  apolloCountry.value =
    COUNTRY_EN[detail.value?.country] || detail.value?.country || '';
  apolloKeywords.value = detail.value?.featuredProducts || '';
  apolloResults.value = [];
  apolloSearched.value = false;
  selectedApollo.value = new Set();
  apolloDialog.value?.open();
};
const runApolloSearch = async () => {
  apolloLoading.value = true;
  selectedApollo.value = new Set();
  try {
    const { data } = await CrmExhibitionAPI.apolloSearch(selectedId.value, {
      country: apolloCountry.value || undefined,
      keywords: apolloKeywords.value || undefined,
    });
    apolloResults.value = camelcaseKeys(data.payload || [], { deep: true });
    apolloSearched.value = true;
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Apollo 搜索失败');
  } finally {
    apolloLoading.value = false;
  }
};
const toggleApollo = idx => {
  const s = new Set(selectedApollo.value);
  if (s.has(idx)) s.delete(idx);
  else s.add(idx);
  selectedApollo.value = s;
};
const addApolloSelected = async () => {
  const picks = [...selectedApollo.value].map(i => apolloResults.value[i]);
  if (!picks.length) {
    useAlert('请先勾选公司');
    return;
  }
  apolloAdding.value = true;
  try {
    const { data } = await CrmExhibitionAPI.addApolloInvites(
      selectedId.value,
      picks
    );
    detail.value = camelcaseKeys(data, { deep: true });
    await loadList();
    apolloDialog.value?.close();
    useAlert(`已建档并加入 ${picks.length} 个新买家`);
  } catch {
    useAlert('加入失败');
  } finally {
    apolloAdding.value = false;
  }
};

// ── 4 步 SOP 分步群发（生成草稿待发）────────────────────────
const SOP_STAGES = [
  { value: 'teaser', label: '① 预告' },
  { value: 'invite', label: '② 邀请函' },
  { value: 'confirm', label: '③ 确认' },
  { value: 'reminder', label: '④ 行前提醒' },
];
const sopDialog = ref(null);
const sopStage = ref('invite');
const sopSelected = ref(new Set());
const sopBusy = ref(false);
const openSop = () => {
  sopStage.value = 'invite';
  sopSelected.value = new Set((detail.value?.invites || []).map(i => i.id));
  sopDialog.value?.open();
};
const toggleSop = id => {
  const s = new Set(sopSelected.value);
  if (s.has(id)) s.delete(id);
  else s.add(id);
  sopSelected.value = s;
};
const toggleAllSop = () => {
  const all = detail.value?.invites || [];
  sopSelected.value =
    sopSelected.value.size === all.length
      ? new Set()
      : new Set(all.map(i => i.id));
};
const runSop = async () => {
  const ids = [...sopSelected.value];
  if (!ids.length) {
    useAlert('请先勾选邀约对象');
    return;
  }
  sopBusy.value = true;
  try {
    const { data } = await CrmExhibitionAPI.generateSopDrafts(
      selectedId.value,
      sopStage.value,
      ids
    );
    sopDialog.value?.close();
    useAlert(
      `已生成 ${data.created} 封「${data.label}」草稿到邮件中心${data.skipped ? `，跳过 ${data.skipped} 封（缺邮箱）` : ''}`
    );
  } catch (e) {
    useAlert(e?.response?.data?.error || '生成草稿失败');
  } finally {
    sopBusy.value = false;
  }
};

// ── 邀请函（AI 生成）+ 阶段流转 ───────────────────────────
const composeDialog = ref(null);
const composeInvite = ref(null);
const composeData = ref({ subject: '', body: '', confirmUrl: '' });
const composing = ref(false);

const openCompose = async invite => {
  composeInvite.value = invite;
  composeData.value = { subject: '', body: '', confirmUrl: invite.confirmUrl };
  composing.value = true;
  composeDialog.value?.open();
  try {
    const { data } = await CrmExhibitionInviteAPI.compose(invite.id);
    composeData.value = camelcaseKeys(data, { deep: true });
  } catch (e) {
    useAlert(e?.response?.data?.error || 'AI 生成邀请函失败');
    composeDialog.value?.close();
  } finally {
    composing.value = false;
  }
};

const copyText = async (text, label = '内容') => {
  try {
    await navigator.clipboard.writeText(text || '');
    useAlert(`${label}已复制`);
  } catch {
    useAlert('复制失败，请手动选择复制');
  }
};

const advance = async (invite, stage) => {
  try {
    await CrmExhibitionInviteAPI.advance(invite.id, stage);
    await refreshBoth();
  } catch {
    useAlert('操作失败');
  }
};

const markInvitedAndClose = async () => {
  await advance(composeInvite.value, 'invited');
  composeDialog.value?.close();
};

const removeInvite = async invite => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`把「${invite.customerName}」移出邀约名单？`)) return;
  try {
    await CrmExhibitionInviteAPI.delete(invite.id);
    await refreshBoth();
  } catch {
    useAlert('移除失败');
  }
};

const stageCount = (d, key) => d?.stageCounts?.[key] || 0;
const fmtDate = s => (s ? s.slice(0, 10) : '');
const dateRange = d => {
  if (!d?.startsOn) return '';
  return d.endsOn && d.endsOn !== d.startsOn
    ? `${fmtDate(d.startsOn)} ~ ${fmtDate(d.endsOn)}`
    : fmtDate(d.startsOn);
};
const locationText = d =>
  [d?.city, countryLabel(d?.country), d?.venue].filter(Boolean).join(' · ');

onMounted(loadList);
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <!-- 头部 -->
    <div
      class="flex items-center justify-between gap-2 px-4 py-3 border-b sm:px-6 sm:py-4 border-n-weak shrink-0 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <div class="flex items-center min-w-0 gap-2">
        <h1 class="text-xl font-semibold truncate text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">展会邀约</h1>
        <span class="text-sm text-n-slate-10"
          >按展会从自己的客户里筛人、AI 生成邀请函、追邀约进度</span
        >
      </div>
      <Button
        label="新建展会"
        icon="i-lucide-plus"
        color="iris"
        size="sm"
        class="shrink-0"
        @click="openCreate"
      />
    </div>

    <div class="flex flex-1 min-h-0">
      <!-- 展会列表 -->
      <aside
        class="flex flex-col w-64 border-r border-n-weak shrink-0 overflow-y-auto sm:w-72"
      >
        <div
          v-if="fetching && !records.length"
          class="p-6 text-sm text-center text-n-slate-10"
        >
          加载中…
        </div>
        <div
          v-else-if="!records.length"
          class="p-6 text-sm text-center text-n-slate-10"
        >
          还没有展会，点右上角「新建展会」开始。
        </div>
        <button
          v-for="ex in records"
          :key="ex.id"
          class="flex flex-col gap-1 px-4 py-3 text-left border-b border-n-weak/60 transition-colors"
          :class="selectedId === ex.id ? 'bg-n-iris-3' : 'hover:bg-n-alpha-1'"
          @click="openDetail(ex.id)"
        >
          <span class="text-sm font-medium truncate text-n-slate-12">{{
            ex.name
          }}</span>
          <span class="text-xs text-n-slate-10 truncate">
            {{
              [countryLabel(ex.country), fmtDate(ex.startsOn)]
                .filter(Boolean)
                .join(' · ') || '—'
            }}
          </span>
          <div class="flex items-center gap-2 mt-0.5">
            <span class="text-2xs text-n-slate-10"
              >邀约 {{ ex.inviteCount }}</span
            >
            <span
              v-if="ex.stageCounts && ex.stageCounts.accepted"
              class="px-1.5 py-0.5 text-2xs rounded-full bg-n-teal-3 text-n-teal-11"
            >
              已接受 {{ ex.stageCounts.accepted }}
            </span>
          </div>
        </button>
      </aside>

      <!-- 详情 -->
      <section class="flex-1 min-w-0 overflow-y-auto">
        <div
          v-if="!detail"
          class="flex items-center justify-center h-full text-sm text-n-slate-10"
        >
          {{ detailLoading ? '加载中…' : '从左侧选择一个展会' }}
        </div>

        <div v-else class="flex flex-col gap-5 p-4 sm:p-6">
          <!-- 展会信息卡 -->
          <div
            class="flex flex-col gap-3 p-4 rounded-2xl border border-n-weak bg-n-solid-1"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <h2 class="text-lg font-semibold truncate text-n-slate-12">
                  {{ detail.name }}
                </h2>
                <div
                  class="flex flex-wrap items-center gap-x-3 gap-y-1 mt-1 text-sm text-n-slate-11"
                >
                  <span v-if="dateRange(detail)">{{ dateRange(detail) }}</span>
                  <span v-if="locationText(detail)">{{
                    locationText(detail)
                  }}</span>
                  <span v-if="detail.boothNo"
                    >展位 {{ detail.boothNo
                    }}{{ detail.hall ? ` · ${detail.hall}` : '' }}</span
                  >
                </div>
                <div
                  v-if="detail.region"
                  class="inline-block mt-2 px-2 py-0.5 text-2xs rounded-full bg-n-iris-3 text-n-iris-11"
                >
                  {{ regionLabel(detail.region) }}
                </div>
                <p
                  v-if="detail.featuredProducts"
                  class="mt-2 text-sm text-n-slate-11"
                >
                  <span class="text-n-slate-10">主打产品：</span
                  >{{ detail.featuredProducts }}
                </p>
              </div>
              <div class="flex items-center gap-2 shrink-0">
                <Button
                  label="编辑"
                  icon="i-lucide-pencil"
                  variant="outline"
                  color="slate"
                  size="sm"
                  @click="openEdit"
                />
                <Button
                  icon="i-lucide-trash-2"
                  variant="ghost"
                  color="ruby"
                  size="sm"
                  @click="deleteExhibition"
                />
              </div>
            </div>
          </div>

          <!-- 邀约漏斗 -->
          <div class="grid grid-cols-4 gap-3">
            <div
              v-for="k in ['pending', 'invited', 'interacted', 'accepted']"
              :key="k"
              class="flex flex-col items-center py-3 rounded-xl border border-n-weak bg-n-solid-1"
            >
              <span class="text-2xl font-semibold text-n-slate-12">{{
                stageCount(detail, k)
              }}</span>
              <span class="text-xs text-n-slate-10">{{
                STAGE_META[k].label
              }}</span>
            </div>
          </div>

          <!-- 名单头 -->
          <div class="flex items-center justify-between gap-2">
            <h3 class="text-base font-semibold text-n-slate-12">
              邀约名单
              <span class="text-sm font-normal text-n-slate-10"
                >（{{ detail.invites.length }}）</span
              >
            </h3>
            <div class="flex items-center gap-2">
              <Button
                v-if="detail.invites.length"
                label="分步群发"
                icon="i-lucide-send"
                variant="outline"
                color="slate"
                size="sm"
                @click="openSop"
              />
              <Button
                label="找新买家"
                icon="i-lucide-globe"
                variant="outline"
                color="iris"
                size="sm"
                @click="openApollo"
              />
              <Button
                label="匹配潜客"
                icon="i-lucide-user-search"
                color="iris"
                size="sm"
                @click="openCandidates"
              />
            </div>
          </div>

          <!-- 名单 -->
          <div
            v-if="!detail.invites.length"
            class="py-10 text-sm text-center text-n-slate-10 rounded-2xl border border-dashed border-n-weak"
          >
            名单还是空的，点「匹配潜客」从你的客户里挑人加入。
          </div>
          <div v-else class="overflow-x-auto">
            <table class="w-full md:min-w-[860px] text-sm">
              <thead>
                <tr class="text-left text-n-slate-10 whitespace-nowrap">
                  <th class="py-2 pr-3 font-medium">客户</th>
                  <th class="py-2 pr-3 font-medium">国家/地区</th>
                  <th class="py-2 pr-3 font-medium">匹配</th>
                  <th class="py-2 pr-3 font-medium">阶段</th>
                  <th class="py-2 pr-3 font-medium">联系人</th>
                  <th class="py-2 pr-3 font-medium text-right">操作</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="inv in detail.invites"
                  :key="inv.id"
                  class="border-t border-n-weak/60"
                >
                  <td class="py-2.5 pr-3">
                    <div
                      class="font-medium text-n-slate-12 truncate max-w-[220px]"
                    >
                      {{ inv.customerName }}
                    </div>
                    <div
                      v-if="inv.replyVisitDate"
                      class="text-2xs text-n-teal-11"
                    >
                      到访 {{ fmtDate(inv.replyVisitDate)
                      }}<span v-if="inv.replyProducts">
                        · {{ inv.replyProducts }}</span
                      >
                    </div>
                  </td>
                  <td class="py-2.5 pr-3 whitespace-nowrap text-n-slate-11">
                    {{
                      [
                        countryLabel(inv.customerCountry),
                        regionLabel(inv.customerRegion),
                      ]
                        .filter(Boolean)
                        .join(' / ') || '—'
                    }}
                  </td>
                  <td class="py-2.5 pr-3 whitespace-nowrap">
                    <span
                      v-if="inv.matchLevel && MATCH_META[inv.matchLevel]"
                      class="px-1.5 py-0.5 text-2xs rounded-full"
                      :class="MATCH_META[inv.matchLevel].cls"
                    >
                      {{ MATCH_META[inv.matchLevel].label }}
                    </span>
                  </td>
                  <td class="py-2.5 pr-3 whitespace-nowrap">
                    <span
                      class="px-1.5 py-0.5 text-2xs rounded-full"
                      :class="STAGE_META[inv.stage].cls"
                    >
                      {{ STAGE_META[inv.stage].label }}
                    </span>
                  </td>
                  <td class="py-2.5 pr-3 whitespace-nowrap text-n-slate-11">
                    {{ inv.contactName || inv.contactEmail || '—' }}
                  </td>
                  <td class="py-2.5 pr-3 whitespace-nowrap text-right">
                    <div class="inline-flex items-center gap-1">
                      <Button
                        icon="i-lucide-link"
                        variant="ghost"
                        color="slate"
                        size="xs"
                        title="复制该客户专属确认链接"
                        @click="copyText(inv.confirmUrl, '确认链接')"
                      />
                      <Button
                        label="邀请函"
                        icon="i-lucide-sparkles"
                        variant="outline"
                        color="iris"
                        size="xs"
                        @click="openCompose(inv)"
                      />
                      <Button
                        v-if="inv.stage === 'pending'"
                        label="标记已邀约"
                        variant="ghost"
                        color="slate"
                        size="xs"
                        @click="advance(inv, 'invited')"
                      />
                      <Button
                        icon="i-lucide-x"
                        variant="ghost"
                        color="slate"
                        size="xs"
                        @click="removeInvite(inv)"
                      />
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </div>

    <!-- 新建/编辑展会 -->
    <Dialog
      ref="exDialog"
      width="2xl"
      overflow-y-auto
      confirm-button-color="iris"
      :title="editingId ? '编辑展会' : '新建展会'"
      :confirm-button-label="editingId ? '保存' : '创建'"
      :is-loading="saving"
      :disable-confirm-button="formInvalid"
      @confirm="saveExhibition"
    >
      <div class="flex flex-col gap-4">
        <Input v-model="form.name" label="展会名称" />
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="mb-0.5 text-heading-3 text-n-slate-12">国家</label>
            <SelectCard v-model="form.country" :options="countryOptions" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="mb-0.5 text-heading-3 text-n-slate-12">地区</label>
            <SelectCard v-model="form.region" :options="regionOptions" />
          </div>
        </div>
        <div class="grid grid-cols-2 gap-4">
          <Input v-model="form.city" label="城市" />
          <Input v-model="form.boothNo" label="展位号" />
        </div>
        <div class="grid grid-cols-2 gap-4">
          <Input v-model="form.venue" label="场馆" />
          <Input v-model="form.hall" label="展馆/馆号" />
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="mb-0.5 text-heading-3 text-n-slate-12"
              >开始日期</label
            >
            <DatePicker v-model="form.startsOn" block clearable />
          </div>
          <div class="flex flex-col gap-1">
            <label class="mb-0.5 text-heading-3 text-n-slate-12"
              >结束日期</label
            >
            <DatePicker v-model="form.endsOn" block clearable />
          </div>
        </div>
        <Input
          v-model="form.website"
          label="展会官网（可选）"
          placeholder="https://…"
        />
        <TextArea
          v-model="form.featuredProducts"
          label="本次主打产品（写进邀请函）"
        />
      </div>
    </Dialog>

    <!-- 匹配潜客 -->
    <Dialog
      ref="candDialog"
      width="3xl"
      overflow-y-auto
      confirm-button-color="iris"
      title="匹配潜客（按国家/地区）"
      :confirm-button-label="`加入名单${selectedCand.size ? `（${selectedCand.size}）` : ''}`"
      :is-loading="adding"
      :disable-confirm-button="!selectedCand.size"
      @confirm="addSelected"
    >
      <div class="flex flex-col gap-3">
        <div class="flex items-center justify-between gap-2">
          <label class="flex items-center gap-2 text-sm text-n-slate-11">
            <input
              v-model="includeLow"
              type="checkbox"
              @change="loadCandidates"
            />
            含低匹配（其它国家/地区的客户）
          </label>
          <button
            v-if="candidates.length"
            class="text-xs text-n-iris-11 hover:underline"
            @click="toggleAllCand"
          >
            {{ selectedCand.size === candidates.length ? '取消全选' : '全选' }}
          </button>
        </div>

        <div
          v-if="candLoading"
          class="py-10 text-sm text-center text-n-slate-10"
        >
          匹配中…
        </div>
        <div
          v-else-if="!candidates.length"
          class="py-10 text-sm text-center text-n-slate-10"
        >
          没有匹配到客户。可勾选「含低匹配」放宽范围。
        </div>
        <div v-else class="flex flex-col gap-1 max-h-[52vh] overflow-y-auto">
          <label
            v-for="c in candidates"
            :key="c.id"
            class="flex items-center gap-3 px-3 py-2 rounded-lg cursor-pointer hover:bg-n-alpha-1"
          >
            <input
              type="checkbox"
              :checked="selectedCand.has(c.id)"
              @change="toggleCand(c.id)"
            />
            <div class="flex-1 min-w-0">
              <div class="text-sm font-medium truncate text-n-slate-12">
                {{ c.name }}
              </div>
              <div class="text-2xs text-n-slate-10 truncate">
                {{
                  [
                    countryLabel(c.tradeCountry),
                    regionLabel(c.tradeRegion),
                    c.primaryContactName,
                  ]
                    .filter(Boolean)
                    .join(' · ') || '—'
                }}
              </div>
            </div>
            <span
              v-if="MATCH_META[c.matchLevel]"
              class="px-1.5 py-0.5 text-2xs rounded-full shrink-0"
              :class="MATCH_META[c.matchLevel].cls"
            >
              {{ MATCH_META[c.matchLevel].label }}
            </span>
          </label>
        </div>
      </div>
    </Dialog>

    <!-- 从 Apollo 找新买家 -->
    <Dialog
      ref="apolloDialog"
      width="3xl"
      overflow-y-auto
      confirm-button-color="iris"
      title="从 Apollo 找新买家（企业库）"
      :confirm-button-label="`建档并加入${selectedApollo.size ? `（${selectedApollo.size}）` : ''}`"
      :is-loading="apolloAdding"
      :disable-confirm-button="!selectedApollo.size"
      @confirm="addApolloSelected"
    >
      <div class="flex flex-col gap-3">
        <p class="text-xs text-n-slate-10">
          按国家 + 行业/产品关键词从 Apollo 企业库搜咱 CRM
          里还没有的公司；选中即建档并加入本展会邀约名单。
        </p>
        <div
          class="grid grid-cols-1 gap-2 sm:grid-cols-[1fr_1.4fr_auto] sm:items-center"
        >
          <Input v-model="apolloCountry" placeholder="国家（英文）" />
          <Input v-model="apolloKeywords" placeholder="关键词" />
          <Button
            label="搜索"
            icon="i-lucide-search"
            color="iris"
            size="sm"
            :is-loading="apolloLoading"
            @click="runApolloSearch"
          />
        </div>

        <div
          v-if="apolloLoading"
          class="py-10 text-sm text-center text-n-slate-10"
        >
          搜索中…
        </div>
        <div
          v-else-if="apolloSearched && !apolloResults.length"
          class="py-10 text-sm text-center text-n-slate-10"
        >
          没搜到（或都已在 CRM 里）。换个关键词/国家试试。
        </div>
        <div
          v-else-if="apolloResults.length"
          class="flex flex-col gap-1 max-h-[48vh] overflow-y-auto"
        >
          <label
            v-for="(c, idx) in apolloResults"
            :key="idx"
            class="flex items-center gap-3 px-3 py-2 rounded-lg cursor-pointer hover:bg-n-alpha-1"
          >
            <input
              type="checkbox"
              :checked="selectedApollo.has(idx)"
              @change="toggleApollo(idx)"
            />
            <div class="flex-1 min-w-0">
              <div class="text-sm font-medium truncate text-n-slate-12">
                {{ c.name }}
              </div>
              <div class="text-2xs text-n-slate-10 truncate">
                {{
                  [c.industry, c.city, c.country, c.domain]
                    .filter(Boolean)
                    .join(' · ') || '—'
                }}
              </div>
            </div>
            <span
              class="px-1.5 py-0.5 text-2xs rounded-full shrink-0 bg-n-iris-3 text-n-iris-11"
            >
              新买家
            </span>
          </label>
        </div>
      </div>
    </Dialog>

    <!-- 4 步 SOP 分步群发（生成草稿到邮件中心，过目再发） -->
    <Dialog
      ref="sopDialog"
      width="2xl"
      overflow-y-auto
      confirm-button-color="iris"
      title="分步群发（生成草稿）"
      :confirm-button-label="`生成草稿${sopSelected.size ? `（${sopSelected.size}）` : ''}`"
      :is-loading="sopBusy"
      :disable-confirm-button="!sopSelected.size"
      @confirm="runSop"
    >
      <div class="flex flex-col gap-3">
        <p class="text-xs text-n-slate-10">
          按 4 步 SOP 给选中客户各生成一封邮件草稿存进「邮件中心 →
          草稿」，你过目后再发；不自动外发。缺邮箱的客户自动跳过。
        </p>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">选择步骤</label>
          <SelectCard v-model="sopStage" :options="SOP_STAGES" />
        </div>
        <div class="flex items-center justify-between">
          <label class="text-heading-3 text-n-slate-12">
            发给（{{ sopSelected.size }}/{{ detail?.invites?.length || 0 }}）
          </label>
          <button
            class="text-xs text-n-iris-11 hover:underline"
            @click="toggleAllSop"
          >
            {{
              sopSelected.size === (detail?.invites?.length || 0)
                ? '取消全选'
                : '全选'
            }}
          </button>
        </div>
        <div class="flex flex-col gap-1 max-h-[44vh] overflow-y-auto">
          <label
            v-for="inv in detail?.invites || []"
            :key="inv.id"
            class="flex items-center gap-3 px-3 py-2 rounded-lg cursor-pointer hover:bg-n-alpha-1"
          >
            <input
              type="checkbox"
              :checked="sopSelected.has(inv.id)"
              @change="toggleSop(inv.id)"
            />
            <div class="flex-1 min-w-0">
              <div class="text-sm font-medium truncate text-n-slate-12">
                {{ inv.customerName }}
              </div>
              <div class="text-2xs text-n-slate-10 truncate">
                {{ inv.contactEmail || '⚠ 无邮箱，将跳过' }}
              </div>
            </div>
            <span
              class="px-1.5 py-0.5 text-2xs rounded-full shrink-0"
              :class="STAGE_META[inv.stage].cls"
            >
              {{ STAGE_META[inv.stage].label }}
            </span>
          </label>
        </div>
      </div>
    </Dialog>

    <!-- 邀请函（AI） -->
    <Dialog
      ref="composeDialog"
      width="2xl"
      overflow-y-auto
      confirm-button-color="iris"
      title="AI 邀请函"
      confirm-button-label="标记已邀约"
      :disable-confirm-button="composing"
      @confirm="markInvitedAndClose"
    >
      <div v-if="composing" class="py-12 text-sm text-center text-n-slate-10">
        AI 正在按展会 + 客户信息生成邀请函…
      </div>
      <div v-else class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <div class="flex items-center justify-between">
            <label class="text-heading-3 text-n-slate-12">主题</label>
            <button
              class="text-xs text-n-iris-11 hover:underline"
              @click="copyText(composeData.subject, '主题')"
            >
              复制
            </button>
          </div>
          <Input v-model="composeData.subject" />
        </div>
        <div class="flex flex-col gap-1">
          <div class="flex items-center justify-between">
            <label class="text-heading-3 text-n-slate-12">正文</label>
            <button
              class="text-xs text-n-iris-11 hover:underline"
              @click="copyText(composeData.body, '正文')"
            >
              复制
            </button>
          </div>
          <TextArea v-model="composeData.body" class="min-h-[220px]" />
        </div>
        <div class="flex items-center gap-2 p-3 rounded-lg bg-n-alpha-1">
          <span class="i-lucide-link size-4 text-n-slate-10 shrink-0" />
          <span class="flex-1 text-xs truncate text-n-slate-11">{{
            composeData.confirmUrl
          }}</span>
          <button
            class="text-xs text-n-iris-11 hover:underline shrink-0"
            @click="copyText(composeData.confirmUrl, '确认链接')"
          >
            复制链接
          </button>
        </div>
        <p class="text-xs text-n-slate-10">
          邮件里已内嵌客户专属的「在线确认到访」链接，客户点开即算已互动、确认即算已接受，会自动回到进度里。
          复制正文到邮件中心发出后，点「标记已邀约」。
        </p>
      </div>
    </Dialog>
  </div>
</template>
