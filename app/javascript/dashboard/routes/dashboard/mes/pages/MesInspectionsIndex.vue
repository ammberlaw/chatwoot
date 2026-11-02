<script setup>
/* global axios */
import { ref, computed, reactive, onMounted, watch } from 'vue';
import { STATUS_TONE } from 'dashboard/helper/statusTone';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesInspectionsStore } from 'dashboard/stores/mes/inspections';
import { useMesMaterialsStore } from 'dashboard/stores/mes/materials';
import MesInspectionAPI from 'dashboard/api/mes/inspections';
import { useMesRole } from 'dashboard/composables/useMesRole';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter } from 'dashboard/composables/store';

import Button from 'dashboard/components-next/button/Button.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';
import { orderSearchText } from 'dashboard/routes/dashboard/mes/orderSearchText';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
import MesColumnFilter from 'dashboard/components-next/mes/MesColumnFilter.vue';
const { accountId } = useAccount();
const { mesCan } = useMesRole();
const store = useMesInspectionsStore();

// 后端每页 15 条，不传 page 就只看得到最新 15 条（生产上 27 条，12 条看不见）。
const ITEMS_PER_PAGE = 15;
const currentPage = ref(1);
const totalCount = computed(() => store.getMeta?.count || 0);
// 列表搜索：工单号 / 成品名 / 不良原因。
const searchQuery = ref('');
// 表头逐列筛选（口径与后端 InspectionsController::COLUMN_LIKE_FILTERS 一一对应）。
const colFilters = reactive({
  kind: '',
  col_object: '',
  col_owner: '',
  result: '',
  col_defect: '',
  col_inspector: '',
  inspected: { from: '', to: '' },
});
const fetchList = () =>
  store.get({
    page: currentPage.value,
    q: searchQuery.value.trim() || undefined,
    kind: colFilters.kind || undefined,
    result: colFilters.result || undefined,
    col_object: colFilters.col_object.trim() || undefined,
    col_owner: colFilters.col_owner.trim() || undefined,
    col_defect: colFilters.col_defect.trim() || undefined,
    col_inspector: colFilters.col_inspector.trim() || undefined,
    from: colFilters.inspected.from || undefined,
    to: colFilters.inspected.to || undefined,
  });
const onSearch = () => {
  currentPage.value = 1;
  fetchList();
};
// 换筛选条件回第 1 页——否则在第 3 页筛出 2 条结果会看到空列表。
const onColFilterChange = () => {
  if (currentPage.value === 1) fetchList();
  else currentPage.value = 1;
};
const materialsStore = useMesMaterialsStore();

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(() => store.getUIFlags.creatingItem);
const day = d => (d ? new Date(d).toLocaleDateString() : '—');

const KIND_LABELS = {
  IQC: '来料检验',
  IPQC: '过程检验',
  FQC: '成品检验',
  AGING: '老化测试',
};
const kindOptions = Object.entries(KIND_LABELS).map(([value, label]) => ({
  value,
  label,
}));
const kindLabel = k => KIND_LABELS[k] || k;
const RESULT = {
  PASS: { label: '合格', cls: STATUS_TONE.done },
  FAIL: { label: '不合格', cls: STATUS_TONE.fail },
  CONDITIONAL: { label: '让步接收', cls: STATUS_TONE.busy },
};

// 表头筛选的列映射。放在 KIND_LABELS / RESULT 之后——它要用这两张表拼下拉项。
const FILTERABLE = {
  kind: {
    type: 'select',
    key: 'kind',
    options: [{ value: '', label: '全部类型' }, ...kindOptions],
  },
  object: {
    type: 'text',
    key: 'col_object',
    placeholder: '工单号 / 物料 / 成品',
  },
  owner: { type: 'text', key: 'col_owner', placeholder: '归属人' },
  result: {
    type: 'select',
    key: 'result',
    options: [
      { value: '', label: '全部结果' },
      ...Object.entries(RESULT).map(([value, v]) => ({
        value,
        label: v.label,
      })),
    ],
  },
  defect: { type: 'text', key: 'col_defect', placeholder: '不良原因' },
  inspector: { type: 'text', key: 'col_inspector', placeholder: '检验员' },
  inspected: { type: 'date', key: 'inspected' },
};
const filterOf = key => FILTERABLE[key];

// 只读查看
const viewDialogRef = ref(null);
const viewing = ref(null);
const openView = r => {
  viewing.value = r;
  viewDialogRef.value?.open();
};
const viewFields = computed(() => {
  const r = viewing.value || {};
  return [
    { label: '检验类型', value: kindLabel(r.kind) },
    {
      label: '对象',
      value: r.productionOrderNo || r.materialName || r.productName,
    },
    { label: '归属人', value: r.productionOrderOwnerName },
    { label: '检验数', value: r.inspectedQty },
    { label: '合格数', value: r.passedQty },
    { label: '不良数', value: r.failedQty },
    { label: '结果', value: RESULT[r.result]?.label || r.result },
    { label: '不良原因', value: r.defectReason },
    { label: '需返修', value: r.needRework ? '是' : '否' },
    { label: '检验员', value: r.inspectorName },
    { label: '检验日期', value: day(r.inspectedAt) },
    { label: '备注', value: r.remark },
  ];
});
// 查看时展示留证附件（照片缩略图 / 视频内联 / 附件下载）。
const viewAttachments = computed(() => {
  const r = viewing.value || {};
  const groups = [];
  if (r.photos?.length)
    groups.push({ label: '检验照片', kind: 'image', files: r.photos });
  if (r.videos?.length)
    groups.push({ label: '检测视频', kind: 'video', files: r.videos });
  if (r.files?.length)
    groups.push({ label: '附件（报告等）', kind: 'file', files: r.files });
  return groups;
});

const productionOrders = ref([]);
const productionOrderOptions = computed(() => [
  { value: '', label: '关联销售订单…' },
  ...productionOrders.value.map(p => ({
    value: String(p.id),
    label: `${p.order_no} · ${p.product_name}`,
    searchText: orderSearchText(p),
  })),
]);
const materialOptions = computed(() =>
  (materialsStore.getRecords || []).map(m => ({
    value: String(m.id),
    label: `${m.name}（${m.unit}）`,
  }))
);

const dialogRef = ref(null);
// 改 / 删只给本人（管理员兜底），和生产报工「谁报工谁删」同一套口径。
// 后端 ensure_owner_or_admin!(:inspector_id) 再判一次，这里只是别让人点了吃 403。
//
// 为什么是删不是作废：质检记录不动库存、不推阶段、不出凭证，作废要冲销的东西一样没有。
// 但看板合格率是按记录加总算的，删一条不良会让它悄悄变好看——所以卡本人。
const { isAdmin } = useAdmin();
const currentUserId = useMapGetter('getCurrentUserID');
const canEditRecord = r =>
  mesCan('quality') && (isAdmin.value || r.inspectorId === currentUserId.value);

const editId = ref(null);
const form = reactive({
  kind: 'FQC',
  productionOrderId: '',
  mesMaterialId: '',
  inspectedQty: '',
  passedQty: '',
  failedQty: '',
  defectReason: '',
  needRework: false,
  remark: '',
});
const { isDirty, markPristine } = useDirtyGuard(() => form);
const isIqc = computed(() => form.kind === 'IQC');
const invalid = computed(() => !Number(form.inspectedQty));

// 检验留证附件：检测视频 / 照片 / 附件。选文件即暂存为 blob（拿 signed_id），提交时带上。
const UPLOAD_KINDS = [
  { kind: 'videos', label: '检测视频', accept: 'video/*' },
  { kind: 'photos', label: '检验照片', accept: 'image/*' },
  { kind: 'files', label: '附件（报告等）', accept: '' },
];
const pending = reactive({ videos: [], photos: [], files: [] });
const uploading = ref(false);
const pickAttachment = async (e, kind) => {
  const list = Array.from(e.target?.files || []);
  e.target.value = '';
  if (!list.length) return;
  uploading.value = true;
  try {
    await Promise.all(
      list.map(async file => {
        const fd = new FormData();
        fd.append('file', file);
        const { data } = await MesInspectionAPI.stageBlob(fd);
        pending[kind].push({ name: data.filename, signedId: data.signed_id });
      })
    );
  } catch {
    useAlert('上传失败，请重试');
  } finally {
    uploading.value = false;
  }
};
const removePending = (kind, i) => pending[kind].splice(i, 1);
const resetAttachments = () => {
  pending.videos = [];
  pending.photos = [];
  pending.files = [];
};

const openCreate = () => {
  editId.value = null;
  Object.assign(form, {
    kind: 'FQC',
    productionOrderId: '',
    mesMaterialId: '',
    inspectedQty: '',
    passedQty: '',
    failedQty: '',
    defectReason: '',
    needRework: false,
    remark: '',
  });
  resetAttachments();
  markPristine();
  dialogRef.value?.open();
};

const openEdit = r => {
  editId.value = r.id;
  Object.assign(form, {
    kind: r.kind,
    productionOrderId: r.productionOrderId ? String(r.productionOrderId) : '',
    mesMaterialId: r.mesMaterialId ? String(r.mesMaterialId) : '',
    inspectedQty: r.inspectedQty ?? '',
    passedQty: r.passedQty ?? '',
    failedQty: r.failedQty ?? '',
    defectReason: r.defectReason || '',
    needRework: !!r.needRework,
    remark: r.remark || '',
  });
  // 已挂的附件不动，这里只放这次新加的
  resetAttachments();
  markPristine();
  dialogRef.value?.open();
};

const removeRecord = async r => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`删除这条${KIND_LABELS[r.kind] || '检验'}记录？删掉后看板的合格率会跟着变。`))
    return;

  const ok = await store.delete(r.id);
  if (ok) {
    useAlert('已删除');
    fetchList();
  } else {
    useAlert('删除失败');
  }
};

const submit = async () => {
  if (invalid.value) return;
  const po = productionOrders.value.find(
    p => String(p.id) === String(form.productionOrderId)
  );
  const payload = {
    kind: form.kind,
    itemType: isIqc.value ? 'MATERIAL' : 'PRODUCT',
    mesMaterialId: isIqc.value ? Number(form.mesMaterialId) || null : null,
    crmProductId: !isIqc.value ? po?.crm_product_id || null : null,
    productionOrderId: !isIqc.value ? form.productionOrderId || null : null,
    inspectedQty: Number(form.inspectedQty) || 0,
    passedQty: Number(form.passedQty) || 0,
    failedQty: Number(form.failedQty) || 0,
    defectReason: form.defectReason,
    needRework: form.needRework,
    remark: form.remark,
    videos: pending.videos.map(p => p.signedId),
    photos: pending.photos.map(p => p.signedId),
    files: pending.files.map(p => p.signedId),
  };
  const ok = editId.value
    ? await store.update({ id: editId.value, ...payload })
    : await store.create(payload);
  if (ok) {
    useAlert(editId.value ? '已保存' : '检验记录已录入');
    dialogRef.value?.close();
    fetchList();
  }
};

watch(currentPage, fetchList);

onMounted(() => {
  fetchList();
  materialsStore.get();
  axios
    .get(`/api/v1/accounts/${accountId.value}/mes/production_orders`, {
      // 下拉要能选到所有在产订单:不传 per_page 后端只给最新 15 条(RESULTS_PER_PAGE),
      // 早一点的单子在下拉里根本找不到。封顶 500。
      params: { per_page: 500 },
    })
    .then(({ data }) => {
      productionOrders.value = data?.payload || [];
    })
    .catch(() => {});
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      class="flex items-center justify-between px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <h1
        class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8"
      >
        质量检验
      </h1>
      <div class="w-64 ms-auto me-2">
        <Input
          v-model="searchQuery"
          size="sm"
          placeholder="搜工单号 / 成品 / 不良原因"
          @keyup.enter="onSearch"
        />
      </div>
      <Button
        v-if="mesCan('quality')"
        label="新增检验"
        color="iris"
        size="sm"
        @click="openCreate"
      />
    </div>

    <MesBoardOwnerBar board-key="mes_inspections_index" />

    <HScrollButtons />
    <div
      class="flex-1 min-h-0 px-4 overflow-auto sm:px-6 [.theme-classic_&]:sm:!px-8"
    >
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <template v-else>
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="r in records"
            :key="r.id"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
            @click="openView(r)"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium text-n-slate-12 truncate">
                {{
                  r.productionOrderNo || r.materialName || r.productName || '—'
                }}
              </span>
              <span
                v-if="RESULT[r.result]"
                class="inline-flex px-2 py-0.5 text-xs rounded-full shrink-0"
                :class="RESULT[r.result].cls"
              >
                {{ RESULT[r.result].label }}
              </span>
              <span class="flex-1" />
              <Button
                label="查看"
                variant="ghost"
                size="sm"
                class="shrink-0"
                @click.stop="openView(r)"
              />
              <Button
                v-if="canEditRecord(r)"
                label="编辑"
                variant="faded"
                size="sm"
                class="shrink-0"
                @click.stop="openEdit(r)"
              />
              <Button
                v-if="canEditRecord(r)"
                label="删除"
                color="ruby"
                variant="ghost"
                size="sm"
                class="shrink-0"
                @click.stop="removeRecord(r)"
              />
            </div>
            <div
              v-if="r.productionOrderNo && r.productName"
              class="mt-1 text-xs text-n-slate-11"
            >
              {{ r.productName }}
            </div>
            <div v-if="r.productSku" class="text-xs text-n-slate-10">
              商品编码 {{ r.productSku }}
            </div>
            <div class="flex flex-wrap gap-x-3 gap-y-1 mt-2">
              <span class="text-xs text-n-slate-11">
                类型：{{ kindLabel(r.kind) }}
              </span>
              <span class="text-xs text-n-slate-11">
                归属人：{{ r.productionOrderOwnerName || '—' }}
              </span>
            </div>
            <div class="flex flex-wrap gap-x-3 gap-y-1 mt-1">
              <span class="text-xs text-n-slate-11">
                检验/合格/不良：{{ r.inspectedQty }} / {{ r.passedQty }} /
                <span :class="r.failedQty > 0 ? 'text-n-ruby-11' : ''">{{
                  r.failedQty
                }}</span>
              </span>
            </div>
            <div class="flex flex-wrap gap-x-3 gap-y-1 mt-1">
              <span class="text-xs text-n-slate-11">
                不良原因：{{ r.defectReason || '—' }}
              </span>
            </div>
            <div class="flex flex-wrap gap-x-3 gap-y-1 mt-1">
              <span class="text-xs text-n-slate-11">
                检验员：{{ r.inspectorName || '—' }}
              </span>
              <span class="text-xs text-n-slate-11">
                日期：{{ day(r.inspectedAt) }}
              </span>
            </div>
          </div>
          <div v-if="!records.length" class="py-10 text-center text-n-slate-11">
            还没有检验记录。
          </div>
        </div>
        <table class="hidden w-full text-sm md:table">
          <!-- 表头白底吸顶：加了逐列筛选，筛选框得一直够得着。 -->
          <thead>
            <tr
              class="text-left text-n-slate-11 [&>th]:sticky [&>th]:top-0 [&>th]:z-10 [&>th]:bg-n-solid-1 [&>th]:border-b [&>th]:border-n-weak"
            >
              <th class="px-3 py-3 font-medium whitespace-nowrap">
                类型
                <MesColumnFilter
                  v-model="colFilters[filterOf('kind').key]"
                  type="select"
                  :options="filterOf('kind').options"
                  @change="onColFilterChange"
                />
              </th>
              <th class="px-3 py-3 font-medium whitespace-nowrap min-w-[160px]">
                对象
                <MesColumnFilter
                  v-model="colFilters[filterOf('object').key]"
                  :placeholder="filterOf('object').placeholder"
                  @change="onColFilterChange"
                />
              </th>
              <th class="px-3 py-3 font-medium whitespace-nowrap min-w-[112px]">
                归属人
                <MesColumnFilter
                  v-model="colFilters[filterOf('owner').key]"
                  :placeholder="filterOf('owner').placeholder"
                  @change="onColFilterChange"
                />
              </th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">
                检验/合格/不良
              </th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">
                结果
                <MesColumnFilter
                  v-model="colFilters[filterOf('result').key]"
                  type="select"
                  :options="filterOf('result').options"
                  @change="onColFilterChange"
                />
              </th>
              <th class="px-3 py-3 font-medium whitespace-nowrap min-w-[96px]">
                不良原因
                <MesColumnFilter
                  v-model="colFilters[filterOf('defect').key]"
                  :placeholder="filterOf('defect').placeholder"
                  @change="onColFilterChange"
                />
              </th>
              <th class="px-3 py-3 font-medium whitespace-nowrap min-w-[112px]">
                检验员
                <MesColumnFilter
                  v-model="colFilters[filterOf('inspector').key]"
                  :placeholder="filterOf('inspector').placeholder"
                  @change="onColFilterChange"
                />
              </th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">
                日期
                <MesColumnFilter
                  v-model="colFilters[filterOf('inspected').key]"
                  type="date"
                  @change="onColFilterChange"
                />
              </th>
              <th class="px-3 py-3" />
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in records" :key="r.id" class="border-b border-n-weak">
              <td class="px-3 py-3 whitespace-nowrap text-n-slate-12">
                {{ kindLabel(r.kind) }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                <div>
                  {{
                    r.productionOrderNo ||
                    r.materialName ||
                    r.productName ||
                    '—'
                  }}
                </div>
                <div
                  v-if="r.productionOrderNo && r.productName"
                  class="text-xs text-n-slate-12"
                >
                  {{ r.productName }}
                </div>
                <div v-if="r.productSku" class="text-xs text-n-slate-10">
                  商品编码 {{ r.productSku }}
                </div>
              </td>
              <td class="px-3 py-3 whitespace-nowrap text-n-slate-11">
                {{ r.productionOrderOwnerName || '—' }}
              </td>
              <td class="px-3 py-3 whitespace-nowrap text-n-slate-11">
                {{ r.inspectedQty }} / {{ r.passedQty }} /
                <span :class="r.failedQty > 0 ? 'text-n-ruby-11' : ''">{{
                  r.failedQty
                }}</span>
              </td>
              <td class="px-3 py-3">
                <span
                  v-if="RESULT[r.result]"
                  class="inline-flex px-2 py-0.5 text-xs rounded-full whitespace-nowrap"
                  :class="RESULT[r.result].cls"
                >
                  {{ RESULT[r.result].label }}
                </span>
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ r.defectReason || '—' }}
              </td>
              <td class="px-3 py-3 whitespace-nowrap text-n-slate-11">
                {{ r.inspectorName || '—' }}
              </td>
              <td class="px-3 py-3 whitespace-nowrap text-n-slate-11">
                {{ day(r.inspectedAt) }}
              </td>
              <td class="px-3 py-3 text-right">
                <div class="flex justify-end gap-1">
                  <Button
                    label="查看"
                    variant="ghost"
                    size="sm"
                    @click="openView(r)"
                  />
                  <Button
                    v-if="canEditRecord(r)"
                    label="编辑"
                    variant="faded"
                    size="sm"
                    @click="openEdit(r)"
                  />
                  <Button
                    v-if="canEditRecord(r)"
                    label="删除"
                    color="ruby"
                    variant="ghost"
                    size="sm"
                    @click="removeRecord(r)"
                  />
                </div>
              </td>
            </tr>
            <tr v-if="!records.length">
              <td colspan="9" class="px-3 py-10 text-center text-n-slate-11">
                还没有检验记录。
              </td>
            </tr>
          </tbody>
        </table>
      </template>

      <PaginationFooter
        v-if="totalCount > ITEMS_PER_PAGE"
        :current-page="currentPage"
        :total-items="totalCount"
        :items-per-page="ITEMS_PER_PAGE"
        class="sticky bottom-0 z-10"
        @update:current-page="currentPage = $event"
      />
    </div>

    <Dialog
      ref="dialogRef"
      :dismissible="false"
      width="3xl"
      confirm-button-color="iris"
      :title="editId ? '编辑质量检验' : '新增质量检验'"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="submit"
      @close="markPristine"
      @save="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">检验类型</label>
            <SelectCard
              size="form"
              :model-value="form.kind"
              :options="kindOptions"
              @update:model-value="v => (form.kind = v)"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              {{ isIqc ? '来料物料' : '关联销售订单' }}
            </label>
            <ComboBox
              v-if="isIqc"
              v-model="form.mesMaterialId"
              :options="materialOptions"
              placeholder="选择物料"
            />
            <ComboBox
              v-else
              :model-value="form.productionOrderId"
              :options="productionOrderOptions"
              placeholder="关联销售订单…"
              search-placeholder="搜 MO 号 / 产品 / 销售订单 / 客户"
              empty-state="没有匹配的生产订单"
              @update:model-value="v => (form.productionOrderId = v)"
            />
          </div>
        </div>
        <div class="grid grid-cols-3 gap-3">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              检验数 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.inspectedQty" type="number" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">合格数</label>
            <Input v-model="form.passedQty" type="number" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">不良数</label>
            <Input v-model="form.failedQty" type="number" />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">不良原因</label>
          <Input v-model="form.defectReason" />
        </div>
        <label class="flex items-center gap-2 text-heading-3 text-n-slate-12">
          <input v-model="form.needRework" type="checkbox" />
          需返修
        </label>

        <!-- 检验留证：检测视频 / 照片 / 附件 -->
        <div class="flex flex-col gap-2 pt-1 border-t border-n-weak">
          <div
            v-for="u in UPLOAD_KINDS"
            :key="u.kind"
            class="flex flex-col gap-1.5"
          >
            <div class="flex items-center gap-2">
              <label class="text-heading-3 text-n-slate-12">{{
                u.label
              }}</label>
              <label
                class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-md cursor-pointer border border-n-weak text-n-slate-11 hover:border-n-brand hover:text-n-slate-12"
              >
                <span class="i-lucide-upload size-3" />
                上传
                <input
                  type="file"
                  multiple
                  :accept="u.accept"
                  class="hidden"
                  @change="e => pickAttachment(e, u.kind)"
                />
              </label>
              <span v-if="uploading" class="text-xs text-n-slate-10">
                上传中…
              </span>
            </div>
            <div v-if="pending[u.kind].length" class="flex flex-wrap gap-1.5">
              <span
                v-for="(f, i) in pending[u.kind]"
                :key="i"
                class="inline-flex items-center gap-1 px-2 py-1 text-xs rounded-md bg-n-alpha-2 text-n-slate-12 max-w-[16rem]"
              >
                <span class="truncate">{{ f.name }}</span>
                <button
                  type="button"
                  class="shrink-0 text-n-slate-10 hover:text-n-ruby-11"
                  @click="removePending(u.kind, i)"
                >
                  <span class="i-lucide-x size-3" />
                </button>
              </span>
            </div>
          </div>
        </div>
      </div>
    </Dialog>

    <MesViewDialog
      ref="viewDialogRef"
      title="质检明细"
      width="3xl"
      :fields="viewFields"
      :attachments="viewAttachments"
    />
  </div>
</template>
