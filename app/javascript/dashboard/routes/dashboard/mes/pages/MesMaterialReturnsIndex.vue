<script setup>
// 生产退料：车间领多了、改单了、料没用完，把料退回仓库。
//
// 后端其实早就支持（库存单 purpose=MATERIAL_RETURN，入库方向，成本侧 return_materials!
// 建层、CostRollupService 从这张工单的料耗里扣回去），缺的只是一个开单入口——
// 生产上 0 张退料单，不是没有这个事，是车间开不出来（2026-10-29 用户提）。
//
// 和生产领料的区别只有两处，别的照抄：
// · 方向反过来：退回哪个仓（to_warehouse_id），不是从哪个仓领（from_warehouse_id）；
// · 可退的量有上限：这张工单**已领 − 已退**。按 BOM 用量算没有意义——
//   退的是实际领出去那批，领了 100 退 120 是账对不上，不是省料。
import { ref, computed, reactive, onMounted, watch } from 'vue';
/* global axios */
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesStockEntriesStore } from 'dashboard/stores/mes/stockEntries';
import { useMesWarehousesStore } from 'dashboard/stores/mes/warehouses';

import Button from 'dashboard/components-next/button/Button.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';
import MesStatusPill from 'dashboard/components-next/mes/MesStatusPill.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import { useMesDocOwner } from 'dashboard/composables/useMesDocOwner';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';
import { orderSearchText } from 'dashboard/routes/dashboard/mes/orderSearchText';
import MesColumnFilter from 'dashboard/components-next/mes/MesColumnFilter.vue';

const { accountId } = useAccount();
const store = useMesStockEntriesStore();
const warehousesStore = useMesWarehousesStore();
const { mesCan } = useMesRole();
const { isMyDoc } = useMesDocOwner();

// 开退料单和开领料单同一拨人：车间提、仓管收（后端 StockEntryPolicy#create? 就是
// stock || report，Mes::StockEntry::BOARD_BY_PURPOSE 也把退料挂在生产领料板块下）。
const canCreate = computed(() => mesCan('stock') || mesCan('report'));
// 删单：仓管随便删，生产岗只能删自己开的草稿（与生产领料同一口径，
// 后端 ensure_can_delete! 卡制单人、destroy 卡已过账）。
const canRemove = e =>
  e.status !== 'CANCELLED' &&
  (mesCan('stock') || (e.status === 'DRAFT' && isMyDoc(e)));

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(() => store.getUIFlags.creatingItem);
const posting = computed(() => store.getUIFlags.updatingItem);
const day = d => (d ? new Date(d).toLocaleDateString() : '—');
const STATUS_LABELS = { DRAFT: '草稿', POSTED: '已过账', CANCELLED: '已作废' };
const whName = id =>
  (warehousesStore.getRecords || []).find(w => w.id === id)?.name || '—';

const ITEMS_PER_PAGE = 15;
const currentPage = ref(1);
const totalCount = computed(() => store.getMeta?.count || 0);
const searchQuery = ref('');
// 表头逐列筛选（后端口径见 StockEntriesController::COLUMN_LIKE_FILTERS）。
const colFilters = reactive({
  col_no: '',
  col_mo: '',
  col_model: '',
  col_to_wh: '',
  status: '',
  posted: { from: '', to: '' },
});
const FILTERABLE = {
  no: { type: 'text', key: 'col_no', placeholder: '退料单号' },
  mo: { type: 'text', key: 'col_mo', placeholder: '生产任务单号' },
  model: { type: 'text', key: 'col_model', placeholder: '型号' },
  warehouse: { type: 'text', key: 'col_to_wh', placeholder: '退回仓库' },
  status: {
    type: 'select',
    key: 'status',
    options: [
      { value: '', label: '全部状态' },
      ...Object.entries(STATUS_LABELS).map(([value, label]) => ({
        value,
        label,
      })),
    ],
  },
  posted: { type: 'date', key: 'posted' },
};
const filterOf = key => FILTERABLE[key];
const fetchList = () =>
  store.get({
    purpose: 'MATERIAL_RETURN',
    page: currentPage.value,
    q: searchQuery.value.trim() || undefined,
    status: colFilters.status || undefined,
    col_no: colFilters.col_no.trim() || undefined,
    col_mo: colFilters.col_mo.trim() || undefined,
    col_model: colFilters.col_model.trim() || undefined,
    col_to_wh: colFilters.col_to_wh.trim() || undefined,
    posted_from: colFilters.posted.from || undefined,
    posted_to: colFilters.posted.to || undefined,
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
watch(currentPage, fetchList);

// ── 可选的生产任务单：领过料的才会出现在这儿 ──
// 一张料都没领过的单没什么可退，摆进来只会让车间在几十条里挑错。
const issuedOrders = ref([]);
const loadIssuedOrders = async () => {
  const { data } = await axios.get(
    `/api/v1/accounts/${accountId.value}/mes/stock_entries`,
    { params: { purpose: 'MATERIAL_ISSUE', per_page: 500 } }
  );
  // ⚠️ 这里走的是裸 axios，拿到的是后端原样的 snake_case；
  // 列表那边的 records 过了 store 才是驼峰，两者别混用（混了就是一片 undefined）。
  const seen = new Map();
  (data?.payload || []).forEach(e => {
    if (!e.production_order_id || e.status !== 'POSTED') return;
    if (!seen.has(e.production_order_id)) {
      seen.set(e.production_order_id, {
        id: e.production_order_id,
        order_no: e.production_order_no,
        product_name: e.product_name,
        owner_name: e.production_order_owner_name,
      });
    }
  });
  issuedOrders.value = [...seen.values()];
};

const orderOptions = computed(() => [
  { value: '', label: '不关联' },
  ...issuedOrders.value.map(o => ({
    value: String(o.id),
    label: `${o.order_no} · ${o.product_name || '—'}`,
    note: o.owner_name || '',
    searchText: orderSearchText(o),
  })),
]);

// ── 这张工单领了什么、退过多少 ──
// 已领 − 已退 = 还能退多少。两边都只认**已过账**的单：草稿还没动库存，
// 拿它算上限会让人退出一个仓库里根本没有的数。
const issuedRows = ref([]);
const loadingRows = ref(false);
const loadIssued = async orderId => {
  issuedRows.value = [];
  if (!orderId) return;

  loadingRows.value = true;
  try {
    const fetch = purpose =>
      axios.get(`/api/v1/accounts/${accountId.value}/mes/stock_entries`, {
        params: { purpose, production_order_id: orderId, per_page: 500 },
      });
    const [issued, returned] = await Promise.all([
      fetch('MATERIAL_ISSUE'),
      fetch('MATERIAL_RETURN'),
    ]);
    const tally = new Map();
    // 同上：裸 axios ＝ snake_case。
    const walk = (payload, sign) =>
      (payload || []).forEach(entry => {
        if (entry.status !== 'POSTED') return;
        (entry.stock_entry_items || []).forEach(it => {
          const key = it.crm_product_id;
          if (!key) return;
          const row = tally.get(key) || {
            crmProductId: key,
            materialNo: it.material_no,
            name: it.material_name || it.product_name,
            unit: it.unit,
            issued: 0,
            returned: 0,
          };
          if (sign > 0) row.issued += Number(it.qty) || 0;
          else row.returned += Number(it.qty) || 0;
          tally.set(key, row);
        });
      });
    walk(issued.data?.payload, 1);
    walk(returned.data?.payload, -1);
    issuedRows.value = [...tally.values()].filter(
      r => r.issued - r.returned > 0
    );
  } finally {
    loadingRows.value = false;
  }
};

// ── 建单 ──
const dialogRef = ref(null);
const editId = ref(null);
const form = reactive({
  productionOrderId: '',
  warehouseId: '',
  remark: '',
  rows: [],
});
const { isDirty, markPristine } = useDirtyGuard(() => form);

const warehouseOptions = computed(() =>
  (warehousesStore.getRecords || []).map(w => ({
    value: String(w.id),
    label: w.name,
  }))
);

// 勾选式明细：选完工单就把这张单**还能退的料**整列推出来，车间勾哪行退哪行。
// 不做「加一行 + 下拉挑料」——能退的东西本来就被「已领 − 已退」框死了，
// 列表外没有可选项；让人去几千条产品档案里搜一颗自己刚领过的料，纯属多绕一圈。
const picked = computed(() => form.rows.filter(r => r.checked));
const allChecked = computed({
  get: () => form.rows.length > 0 && picked.value.length === form.rows.length,
  set: v =>
    form.rows.forEach(r => {
      r.checked = v;
    }),
});

// 超领退回是账对不上，不是省料，所以在前端就拦住；后端还有库存和成本两道。
const rowError = row => {
  if (!row.checked) return '';
  const qty = Number(row.qty);
  if (!(qty > 0)) return '填写数量';
  return qty > row.remain ? `最多 ${row.remain}` : '';
};
const invalid = computed(
  () =>
    !form.warehouseId ||
    !picked.value.length ||
    form.rows.some(r => rowError(r))
);

const openCreate = async () => {
  editId.value = null;
  Object.assign(form, {
    productionOrderId: '',
    warehouseId: warehouseOptions.value[0]?.value || '',
    remark: '',
    rows: [],
  });
  issuedRows.value = [];
  markPristine();
  dialogRef.value?.open();
};

watch(
  () => form.productionOrderId,
  async id => {
    await loadIssued(id);
    // 推料：默认全不勾、数量留空。不预勾也不预填可退量——
    // 退料是「这次实际退回多少」，替人填一个数等于诱导他直接点保存。
    form.rows = issuedRows.value.map(r => ({
      ...r,
      remain: r.issued - r.returned,
      checked: false,
      qty: '',
    }));
  }
);

const submit = async () => {
  if (invalid.value) return;

  const payload = {
    purpose: 'MATERIAL_RETURN',
    productionOrderId: form.productionOrderId || null,
    // 退料是入库方向：货回到这个仓。
    toWarehouseId: Number(form.warehouseId),
    remark: form.remark || null,
    stockEntryItemsAttributes: picked.value.map(r => ({
      // 退回的是原料仓那批采购件，和领料记的是同一本结存账，item_type 必须同为 MATERIAL。
      itemType: 'MATERIAL',
      crmProductId: Number(r.crmProductId),
      qty: Number(r.qty),
      warehouseId: Number(form.warehouseId),
    })),
  };
  try {
    const ok = await store.create(payload);
    if (ok) {
      useAlert(`退料单 ${ok.entryNo} 已保存，过账后料才真正回到库存`);
      markPristine();
      dialogRef.value?.close();
      fetchList();
    }
  } catch (error) {
    useAlert(error.message || '保存失败');
  }
};

const postEntry = async entry => {
  try {
    const ok = await store.post(entry.id);
    if (ok) useAlert(`${ok.entryNo} 已过账，料已退回库存`);
  } catch (error) {
    useAlert(error.message || '过账失败');
  }
};

const removeEntry = async e => {
  if (e.status === 'POSTED') {
    // eslint-disable-next-line no-alert
    if (
      !window.confirm(`确定作废退料单 ${e.entryNo}？退回的料会从库存里扣走。`)
    )
      return;
    try {
      const ok = await store.cancel(e.id);
      if (ok) useAlert(`${e.entryNo} 已作废`);
    } catch (error) {
      useAlert(error.message || '作废失败');
    }
    return;
  }
  // eslint-disable-next-line no-alert
  if (!window.confirm(`确定删除退料单 ${e.entryNo}？删除后不可恢复。`)) return;
  try {
    const ok = await store.delete(e.id);
    if (ok) useAlert('已删除');
  } catch (error) {
    useAlert(error.message || '删除失败');
  }
};

// ── 只读查看 ──
const viewDialogRef = ref(null);
const viewing = ref(null);
const openView = e => {
  viewing.value = e;
  viewDialogRef.value?.open();
};
const viewFields = computed(() => {
  const e = viewing.value || {};
  return [
    { label: '单号', value: e.entryNo },
    { label: '生产任务单', value: e.productionOrderNo || '—' },
    { label: '型号', value: e.productName || '—' },
    { label: '退回仓库', value: whName(e.toWarehouseId) },
    { label: '状态', value: STATUS_LABELS[e.status] },
    { label: '过账时间', value: day(e.postedAt) },
    { label: '备注', value: e.remark || '—' },
  ];
});
const viewColumns = [
  { label: '物料编码', key: 'materialNo' },
  { label: '物料名称', key: 'name' },
  { label: '退回量', key: 'qty', align: 'right' },
  { label: '单位', key: 'unit' },
];
const viewItems = computed(() =>
  (viewing.value?.stockEntryItems || []).map(it => ({
    materialNo: it.materialNo,
    name: it.materialName || it.productName,
    qty: it.qty,
    unit: it.unit,
  }))
);

onMounted(() => {
  fetchList();
  warehousesStore.get();
  loadIssuedOrders();
});
</script>

<template>
  <div class="flex flex-col gap-4 p-6">
    <div class="flex flex-wrap items-center gap-3">
      <h1 class="text-xl font-semibold text-n-slate-12">生产退料</h1>
      <div class="flex items-center gap-2 ml-auto">
        <Input
          v-model="searchQuery"
          placeholder="搜索单号、工单、物料"
          class="reset-base !h-9 w-64"
          @keyup.enter="onSearch"
        />
        <Button
          v-if="canCreate"
          label="新建退料单"
          color="iris"
          @click="openCreate"
        />
      </div>
    </div>

    <MesBoardOwnerBar board-key="mes_material_issues_index" />

    <div class="overflow-x-auto border rounded-lg border-n-weak">
      <!-- 同采购退料：w-max 按内容撑开（写 w-full 的话列一多中文会被逐字折成竖排），
           min-w-full 保证数据少时也铺满。弹窗里那张明细表不改——它在定宽容器里，列就该铺满。 -->
      <table class="w-max min-w-full text-sm">
        <!-- 表头白底吸顶，与原料入库/销售订单一致。原来写的是 bg-n-alpha-1 灰底块，
             全站只有这一页是灰条（2026-10-31 反馈「这个 ui 设计怎么和其它板块的不一样」）。 -->
        <thead
          class="text-left text-n-slate-11 [&>tr>th]:sticky [&>tr>th]:top-0 [&>tr>th]:z-10 [&>tr>th]:bg-n-solid-1 [&>tr>th]:border-b [&>tr>th]:border-n-weak"
        >
          <tr>
            <th class="px-3 py-2 font-medium whitespace-nowrap">
              单号
              <MesColumnFilter
                v-model="colFilters[filterOf('no').key]"
                :placeholder="filterOf('no').placeholder"
                @change="onColFilterChange"
              />
            </th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">
              生产任务单
              <MesColumnFilter
                v-model="colFilters[filterOf('mo').key]"
                :placeholder="filterOf('mo').placeholder"
                @change="onColFilterChange"
              />
            </th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">
              型号
              <MesColumnFilter
                v-model="colFilters[filterOf('model').key]"
                :placeholder="filterOf('model').placeholder"
                @change="onColFilterChange"
              />
            </th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">
              退回仓库
              <MesColumnFilter
                v-model="colFilters[filterOf('warehouse').key]"
                :placeholder="filterOf('warehouse').placeholder"
                @change="onColFilterChange"
              />
            </th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">
              状态
              <MesColumnFilter
                v-model="colFilters[filterOf('status').key]"
                type="select"
                :options="filterOf('status').options"
                @change="onColFilterChange"
              />
            </th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">
              过账时间
              <MesColumnFilter
                v-model="colFilters[filterOf('posted').key]"
                type="date"
                @change="onColFilterChange"
              />
            </th>
            <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
              操作
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="e in records"
            :key="e.id"
            class="border-t border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-3 py-3 font-mono whitespace-nowrap">
              {{ e.entryNo }}
            </td>
            <td class="px-3 py-3 whitespace-nowrap">
              {{ e.productionOrderNo || '—' }}
            </td>
            <td
              class="px-3 py-3 max-w-[16rem] truncate whitespace-nowrap"
              :title="e.productName"
            >
              {{ e.productName || '—' }}
            </td>
            <td class="px-3 py-3 whitespace-nowrap">
              {{ whName(e.toWarehouseId) }}
            </td>
            <td class="px-3 py-3">
              <MesStatusPill :label="STATUS_LABELS[e.status]" />
            </td>
            <td class="px-3 py-3 text-n-slate-11">{{ day(e.postedAt) }}</td>
            <td class="px-3 py-3 text-right">
              <div class="flex justify-end gap-1">
                <Button
                  label="查看"
                  variant="ghost"
                  size="sm"
                  @click="openView(e)"
                />
                <Button
                  v-if="e.status === 'DRAFT' && mesCan('stock')"
                  label="过账"
                  color="iris"
                  size="sm"
                  :is-loading="posting"
                  @click="postEntry(e)"
                />
                <Button
                  v-if="canRemove(e)"
                  :label="e.status === 'POSTED' ? '作废' : '删单'"
                  color="ruby"
                  variant="ghost"
                  size="sm"
                  :is-loading="posting"
                  @click="removeEntry(e)"
                />
              </div>
            </td>
          </tr>
          <tr v-if="!records.length && !isFetching">
            <td colspan="7" class="px-3 py-10 text-center text-n-slate-11">
              暂无退料单
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <PaginationFooter
      v-if="totalCount > ITEMS_PER_PAGE"
      v-model="currentPage"
      :total-items="totalCount"
      :items-per-page="ITEMS_PER_PAGE"
    />

    <Dialog
      ref="dialogRef"
      width="3xl"
      overflow-y-auto
      :dismissible="false"
      :is-dirty="isDirty"
      title="新建退料单"
      confirm-button-label="保存"
      confirm-button-color="iris"
      :disable-confirm-button="invalid"
      :is-loading="saving"
      @confirm="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div class="flex flex-col gap-1.5">
            <label class="text-heading-3 text-n-slate-12">生产任务单</label>
            <ComboBox
              v-model="form.productionOrderId"
              :options="orderOptions"
              placeholder="选择"
              search-placeholder="搜索"
              empty-state="无可选项"
            />
          </div>
          <div class="flex flex-col gap-1.5">
            <label class="text-heading-3 text-n-slate-12">
              退回仓库 <span class="text-n-ruby-11">*</span>
            </label>
            <SelectCard
              v-model="form.warehouseId"
              :options="warehouseOptions"
              block
            />
          </div>
        </div>

        <div class="flex flex-col gap-2">
          <div class="flex items-center gap-2">
            <span class="text-heading-3 text-n-slate-12">退回明细</span>
            <span v-if="loadingRows" class="text-xs text-n-slate-11">
              读取中…
            </span>
            <span
              v-else-if="form.productionOrderId && !form.rows.length"
              class="text-xs text-n-slate-11"
            >
              无可退物料
            </span>
            <span
              v-else-if="!form.productionOrderId"
              class="text-xs text-n-slate-11"
            >
              先选生产任务单
            </span>
            <span v-if="picked.length" class="ml-auto text-xs text-n-slate-11">
              已选 {{ picked.length }} / {{ form.rows.length }}
            </span>
          </div>

          <div
            v-if="form.rows.length"
            class="overflow-hidden border rounded-lg border-n-weak"
          >
            <table class="w-full text-sm">
              <thead class="text-xs text-left text-n-slate-11 bg-n-alpha-1">
                <tr>
                  <th class="w-10 px-3 py-2">
                    <input
                      v-model="allChecked"
                      type="checkbox"
                      class="align-middle"
                    />
                  </th>
                  <th class="px-3 py-2 font-medium whitespace-nowrap">
                    物料编码
                  </th>
                  <th class="px-3 py-2 font-medium">物料名称</th>
                  <th
                    class="px-3 py-2 font-medium text-right whitespace-nowrap"
                  >
                    已领
                  </th>
                  <th
                    class="px-3 py-2 font-medium text-right whitespace-nowrap"
                  >
                    已退
                  </th>
                  <th
                    class="px-3 py-2 font-medium text-right whitespace-nowrap"
                  >
                    可退
                  </th>
                  <th class="px-3 py-2 font-medium w-36 whitespace-nowrap">
                    退回数量
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="row in form.rows"
                  :key="row.crmProductId"
                  class="border-t border-n-weak"
                  :class="row.checked ? 'bg-n-alpha-1' : ''"
                >
                  <td class="px-3 py-2">
                    <input
                      v-model="row.checked"
                      type="checkbox"
                      class="align-middle"
                    />
                  </td>
                  <td
                    class="px-3 py-2 font-mono whitespace-nowrap text-n-slate-11"
                  >
                    {{ row.materialNo || '—' }}
                  </td>
                  <td class="px-3 py-2">{{ row.name || '—' }}</td>
                  <td class="px-3 py-2 text-right tabular-nums text-n-slate-11">
                    {{ row.issued }}
                  </td>
                  <td class="px-3 py-2 text-right tabular-nums text-n-slate-11">
                    {{ row.returned }}
                  </td>
                  <td class="px-3 py-2 font-medium text-right tabular-nums">
                    {{ row.remain }}{{ row.unit || '' }}
                  </td>
                  <td class="px-3 py-2">
                    <Input
                      v-model="row.qty"
                      type="number"
                      min="0"
                      :max="row.remain"
                      :disabled="!row.checked"
                      size="sm"
                      :message="rowError(row)"
                      :message-type="rowError(row) ? 'error' : 'info'"
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="flex flex-col gap-1.5">
          <label class="text-heading-3 text-n-slate-12">备注</label>
          <Input v-model="form.remark" />
        </div>
      </div>
    </Dialog>

    <MesViewDialog
      ref="viewDialogRef"
      title="退料单"
      :fields="viewFields"
      :columns="viewColumns"
      :items="viewItems"
    />
  </div>
</template>
