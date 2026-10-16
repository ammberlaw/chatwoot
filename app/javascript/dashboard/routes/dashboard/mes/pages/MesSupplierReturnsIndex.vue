<script setup>
// 退料返修：把料退给供应商修，修好登记回来。
//
// 用户原话：「我这边退料出去，多久能回来？是不是要设置一个退出去的时间跟物料返修回来时间呢；
// 是不是需要再做个退料返修回来的模块呢？」
// 所以这页的主角是**两个日期和中间那段天数**，不是数量。
// 本期只记台账、不动库存（返修回来要不要重新入库/质检用户还没定）。
import { ref, reactive, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesRole } from 'dashboard/composables/useMesRole';
import { useMesSupplierReturnsStore } from 'dashboard/stores/mes/supplierReturns';
import MesSupplierAPI from 'dashboard/api/mes/suppliers';
import MesProductionOrderAPI from 'dashboard/api/mes/productionOrders';
import { STATUS_TONE } from 'dashboard/helper/statusTone';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import MesProductPicker from 'dashboard/components-next/mes/MesProductPicker.vue';

const store = useMesSupplierReturnsStore();
const { accountId } = useAccount();
const { mesCan } = useMesRole();
const canWrite = computed(() => mesCan('purchase') || mesCan('stock'));

const ITEMS_PER_PAGE = 20;
const STATUS_CLASS = {
  DRAFT: STATUS_TONE.idle,
  SENT: STATUS_TONE.busy,
  PARTIAL: STATUS_TONE.flow,
  RETURNED: STATUS_TONE.done,
  CLOSED: STATUS_TONE.idle,
};
const STATUS_FILTERS = [
  { value: '', label: '全部' },
  { value: 'SENT', label: '已退出' },
  { value: 'PARTIAL', label: '部分返回' },
  { value: 'RETURNED', label: '已返回' },
];

const records = computed(() => store.getRecords);
const totalCount = computed(() => Number(store.getMeta?.count || 0));
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(
  () => store.getUIFlags.creatingItem || store.getUIFlags.updatingItem
);

const currentPage = ref(1);
const activeStatus = ref('');
const searchQuery = ref('');

const fetchList = () =>
  store.get({
    page: currentPage.value,
    status: activeStatus.value || undefined,
    q: searchQuery.value.trim() || undefined,
  });

const onPage = page => {
  currentPage.value = page;
  fetchList();
};
const onFilter = value => {
  activeStatus.value = value;
  currentPage.value = 1;
  fetchList();
};

// 供应商、生产订单下拉
const supplierOptions = ref([]);
const orderOptions = ref([]);
const loadOptions = async () => {
  const [suppliers, orders] = await Promise.all([
    MesSupplierAPI.get({ per_page: 300 }).catch(() => null),
    MesProductionOrderAPI.get({ per_page: 100 }).catch(() => null),
  ]);
  supplierOptions.value = (suppliers?.data?.payload || []).map(s => ({
    value: s.id,
    label: s.name,
  }));
  orderOptions.value = (orders?.data?.payload || []).map(o => ({
    value: o.id,
    label: `${o.order_no}${o.product_name ? ` · ${o.product_name}` : ''}`,
  }));
};

// ── 新建 ──
const formDialogRef = ref(null);
const blankRow = () => ({ crmProductId: '', qty: '', unit: '', remark: '' });
const form = reactive({
  mesSupplierId: '',
  productionOrderId: '',
  reason: '',
  remark: '',
  rows: [blankRow()],
});
const productLabels = reactive({});
const invalid = computed(
  () =>
    !form.mesSupplierId ||
    !form.rows.some(r => r.crmProductId && Number(r.qty) > 0)
);

const openCreate = () => {
  Object.assign(form, {
    mesSupplierId: '',
    productionOrderId: '',
    reason: '',
    remark: '',
    rows: [blankRow()],
  });
  formDialogRef.value?.open();
};
const addRow = () => form.rows.push(blankRow());
const removeRow = i => form.rows.splice(i, 1);
const onProductPicked = (row, product) => {
  if (!product) return;
  productLabels[product.id] =
    `${product.sku || ''} ${product.name || ''}`.trim();
  row.unit = row.unit || product.unit || '';
};

const submit = async () => {
  if (invalid.value) return;
  try {
    await store.create({
      mes_supplier_id: form.mesSupplierId,
      production_order_id: form.productionOrderId || null,
      reason: form.reason.trim() || null,
      remark: form.remark.trim() || null,
      items_attributes: form.rows
        .filter(r => r.crmProductId && Number(r.qty) > 0)
        .map(r => ({
          crm_product_id: r.crmProductId,
          qty: Number(r.qty),
          unit: r.unit || null,
          remark: r.remark || null,
        })),
    });
    useAlert('退料单已建好，退出去时点「退出」记日期');
    formDialogRef.value?.close();
    fetchList();
  } catch (error) {
    useAlert(error?.message || '保存失败');
  }
};

// ── 退出 ──
const sendOut = async record => {
  try {
    await store.sendOut(record.id);
    useAlert(`${record.returnNo} 已记为今天退出`);
  } catch (error) {
    useAlert(error?.message || '操作失败');
  }
};

// ── 登记返回 ──
const backDialogRef = ref(null);
const backing = ref(null);
const backRows = ref([]);
const backDate = ref('');
const openReceive = record => {
  backing.value = record;
  backDate.value = new Date().toISOString().slice(0, 10);
  backRows.value = (record.items || []).map(it => ({
    id: it.id,
    label: `${it.productSku || ''} ${it.productName || ''}`.trim() || '—',
    outstanding: Number(it.outstandingQty || 0),
    qty: '',
  }));
  backDialogRef.value?.open();
};
const submitReceive = async () => {
  const rows = backRows.value
    .filter(r => Number(r.qty) > 0)
    .map(r => ({ id: r.id, returned_qty: Number(r.qty) }));
  if (!rows.length) return;
  try {
    await store.receiveBack(backing.value.id, rows, backDate.value);
    useAlert(`${backing.value.returnNo} 已登记返回`);
    backDialogRef.value?.close();
  } catch (error) {
    useAlert(error?.message || '登记失败');
  }
};

const removeRecord = async record => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`删除退料单「${record.returnNo}」？`)) return;
  try {
    await store.delete(record.id);
    useAlert('已删除');
    fetchList();
  } catch (error) {
    useAlert(error?.message || '删除失败');
  }
};

onMounted(() => {
  fetchList();
  loadOptions();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      class="flex items-center justify-between px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:sm:!px-8"
    >
      <h1 class="text-xl font-semibold text-n-slate-12">退料返修</h1>
      <Button
        v-if="canWrite"
        label="新建退料单"
        color="iris"
        size="sm"
        @click="openCreate"
      />
    </div>

    <div
      class="flex items-center gap-2 px-4 pb-3 sm:px-6 [.theme-classic_&]:sm:!px-8"
    >
      <button
        v-for="f in STATUS_FILTERS"
        :key="f.value"
        type="button"
        class="px-3 py-1 text-sm rounded-md reset-base"
        :class="
          activeStatus === f.value
            ? 'bg-n-slate-12 text-n-slate-1'
            : 'text-n-slate-11 hover:bg-n-alpha-1'
        "
        @click="onFilter(f.value)"
      >
        {{ f.label }}
      </button>
      <div class="w-64 ms-auto">
        <Input
          v-model="searchQuery"
          size="sm"
          placeholder="搜单号 / 退料原因"
          @keyup.enter="onPage(1)"
        />
      </div>
    </div>

    <div
      class="flex-1 min-h-0 px-4 pb-4 overflow-auto sm:px-6 sm:pb-6 [.theme-classic_&]:sm:!px-8"
    >
      <table class="w-full text-sm">
        <thead class="text-xs text-n-slate-11">
          <tr class="border-b border-n-weak">
            <th class="px-3 py-2 font-medium text-left">单号</th>
            <th class="px-3 py-2 font-medium text-left">供应商</th>
            <th class="px-3 py-2 font-medium text-left">生产订单</th>
            <th class="px-3 py-2 font-medium text-left">退料原因</th>
            <th class="px-3 py-2 font-medium text-left">退出</th>
            <th class="px-3 py-2 font-medium text-left">返回</th>
            <th class="px-3 py-2 font-medium text-right">在外天数</th>
            <th class="px-3 py-2 font-medium text-left">状态</th>
            <th class="px-3 py-2" />
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="r in records"
            :key="r.id"
            class="border-b border-n-weak/60 hover:bg-n-alpha-1"
          >
            <td class="px-3 py-2 whitespace-nowrap text-n-slate-12">
              {{ r.returnNo }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ r.supplierName || '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11 whitespace-nowrap">
              {{ r.productionOrderNo || '—' }}
            </td>
            <td class="px-3 py-2 max-w-[16rem] truncate text-n-slate-11">
              {{ r.reason || '—' }}
            </td>
            <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
              {{ r.sentOn || '—' }}
            </td>
            <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
              {{ r.returnedOn || '—' }}
            </td>
            <!-- 还没回来的标琥珀：这列就是用户要盯的「退出去多久了」 -->
            <td
              class="px-3 py-2 text-right tabular-nums whitespace-nowrap"
              :class="r.out ? 'text-n-amber-11' : 'text-n-slate-11'"
            >
              {{ r.daysOut == null ? '—' : `${r.daysOut} 天` }}
            </td>
            <td class="px-3 py-2">
              <span
                class="inline-block px-2 py-0.5 text-xs rounded whitespace-nowrap"
                :class="STATUS_CLASS[r.status]"
              >
                {{ r.statusLabel }}
              </span>
            </td>
            <td class="px-3 py-2">
              <div class="flex items-center justify-end gap-1">
                <Button
                  v-if="canWrite && !r.sentOn"
                  label="退出"
                  color="iris"
                  size="xs"
                  :is-loading="saving"
                  @click="sendOut(r)"
                />
                <Button
                  v-if="canWrite && r.sentOn && r.status !== 'RETURNED'"
                  label="登记返回"
                  variant="faded"
                  color="slate"
                  size="xs"
                  @click="openReceive(r)"
                />
                <button
                  v-if="canWrite && !r.sentOn"
                  type="button"
                  title="删除"
                  class="i-lucide-trash-2 size-4 text-n-slate-10 hover:text-n-ruby-11"
                  @click="removeRecord(r)"
                />
              </div>
            </td>
          </tr>
          <tr v-if="!records.length && !isFetching">
            <td colspan="9" class="px-3 py-10 text-center text-n-slate-11">
              还没有退料单。
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <PaginationFooter
      :current-page="currentPage"
      :total-items="totalCount"
      :items-per-page="ITEMS_PER_PAGE"
      @update:current-page="onPage"
    />

    <!-- 新建 -->
    <Dialog
      ref="formDialogRef"
      width="3xl"
      overflow-y-auto
      title="新建退料单"
      confirm-button-label="保存"
      :disable-confirm-button="invalid"
      :is-loading="saving"
      @confirm="submit"
    >
      <div class="flex flex-col gap-3">
        <div class="grid grid-cols-2 gap-3">
          <div class="flex flex-col gap-1">
            <label class="text-label text-n-slate-12">
              退给哪家供应商 <span class="text-n-ruby-11">*</span>
            </label>
            <ComboBox
              v-model="form.mesSupplierId"
              :options="supplierOptions"
              placeholder="选供应商"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-label text-n-slate-12">关联生产订单</label>
            <ComboBox
              v-model="form.productionOrderId"
              :options="orderOptions"
              placeholder="选填"
            />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-label text-n-slate-12">退料原因</label>
          <Input
            v-model="form.reason"
            size="sm"
            placeholder="例：屏幕显示不良，退回返修"
          />
        </div>

        <div class="flex items-center justify-between">
          <span class="text-heading-3 text-n-slate-12">退料明细</span>
          <Button
            label="加一行"
            icon="i-lucide-plus"
            color="slate"
            variant="faded"
            size="xs"
            @click="addRow"
          />
        </div>
        <div
          v-for="(row, i) in form.rows"
          :key="i"
          class="flex items-center gap-2 p-2 border rounded-lg border-n-weak"
        >
          <span class="w-5 text-xs text-center shrink-0 text-n-slate-10">
            {{ i + 1 }}
          </span>
          <div class="flex-1 min-w-0">
            <MesProductPicker
              materials-only
              :account-id="accountId"
              :model-value="row.crmProductId"
              :display-text="productLabels[row.crmProductId] || ''"
              placeholder="选物料（编码/名称/规格）"
              @update:model-value="v => (row.crmProductId = v)"
              @select="pd => onProductPicked(row, pd)"
            />
          </div>
          <div class="w-24 shrink-0">
            <Input
              v-model="row.qty"
              size="sm"
              type="number"
              placeholder="数量"
            />
          </div>
          <div class="w-20 shrink-0">
            <Input v-model="row.unit" size="sm" placeholder="单位" />
          </div>
          <button
            type="button"
            class="shrink-0 i-lucide-x size-4 text-n-slate-10 hover:text-n-ruby-11"
            :disabled="form.rows.length <= 1"
            @click="removeRow(i)"
          />
        </div>

        <div class="flex flex-col gap-1">
          <label class="text-label text-n-slate-12">备注</label>
          <Input v-model="form.remark" size="sm" placeholder="选填" />
        </div>
      </div>
    </Dialog>

    <!-- 登记返回 -->
    <Dialog
      ref="backDialogRef"
      width="xl"
      title="登记返修回来"
      confirm-button-label="确认"
      @confirm="submitReceive"
    >
      <div class="flex flex-col gap-3">
        <div class="flex items-center gap-2">
          <span class="text-label text-n-slate-12">回来的日期</span>
          <div class="w-44">
            <DatePicker v-model="backDate" />
          </div>
        </div>
        <div
          v-for="row in backRows"
          :key="row.id"
          class="flex items-center gap-2 text-sm"
        >
          <span class="flex-1 min-w-0 truncate text-n-slate-12">
            {{ row.label }}
          </span>
          <span class="text-xs shrink-0 text-n-slate-10">
            还差 {{ row.outstanding }}
          </span>
          <div class="w-24 shrink-0">
            <Input
              v-model="row.qty"
              size="sm"
              type="number"
              placeholder="回来多少"
            />
          </div>
        </div>
        <p class="text-xs text-n-slate-10">
          只记台账，不自动入库——要不要重新入库 / 质检还没定，定了再接。
        </p>
      </div>
    </Dialog>
  </div>
</template>
