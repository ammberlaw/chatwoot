<script setup>
/* global axios */
import { ref, computed, reactive, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesBomsStore } from 'dashboard/stores/mes/boms';
import MesBomAPI from 'dashboard/api/mes/boms';

import Button from 'dashboard/components-next/button/Button.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const { accountId } = useAccount();
const store = useMesBomsStore();
const { mesCan } = useMesRole();

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(
  () => store.getUIFlags.creatingItem || store.getUIFlags.updatingItem
);

// 按阶段预估天数（不含销售出库/物流）。
const LEAD_STAGES = [
  { key: 'purchasingDays', label: '采购原料' },
  { key: 'materialInboundDays', label: '原料入库' },
  { key: 'pickingDays', label: '生产领料' },
  { key: 'productionDays', label: '生产' },
  { key: 'fgInboundDays', label: '成品入库' },
];

const products = ref([]);
const productOptions = computed(() =>
  products.value.map(p => ({ value: String(p.id), label: p.name }))
);

const dialogRef = ref(null);
const editingId = ref(null);
const editingStatus = ref(null); // 编辑时的原状态：已下发则只显示「保存」
const removedItemIds = ref([]);
const releasingId = ref(null);
const blankLeadDays = () =>
  Object.fromEntries(LEAD_STAGES.map(s => [s.key, '']));
// 用料明细每行照生产任务单直接填。
const blankRow = () => ({
  materialNo: '',
  materialName: '',
  specification: '',
  unit: '',
  qty: '',
  remark: '',
});
const form = reactive({
  crmProductId: '',
  baseQty: '1',
  unit: '台',
  ...blankLeadDays(),
  rows: [], // { id?, materialNo, materialName, specification, unit, qty, remark }
});

const totalLeadDays = computed(() =>
  LEAD_STAGES.reduce((sum, s) => sum + (Number(form[s.key]) || 0), 0)
);

const invalid = computed(
  () =>
    !form.rows.length ||
    form.rows.some(r => !r.materialName.trim() || !Number(r.qty))
);

const addRow = () => form.rows.push(blankRow());
const removeRow = i => {
  const [removed] = form.rows.splice(i, 1);
  if (removed?.id) removedItemIds.value.push(removed.id);
};

const openCreate = () => {
  editingId.value = null;
  editingStatus.value = null;
  removedItemIds.value = [];
  Object.assign(form, {
    crmProductId: '',
    baseQty: '1',
    unit: '台',
    ...blankLeadDays(),
    rows: [blankRow()],
  });
  dialogRef.value?.open();
};
const openEdit = bom => {
  editingId.value = bom.id;
  editingStatus.value = bom.status;
  removedItemIds.value = [];
  Object.assign(form, {
    crmProductId: bom.crmProductId ? String(bom.crmProductId) : '',
    baseQty: String(bom.baseQty ?? '1'),
    unit: bom.unit || '',
    ...Object.fromEntries(LEAD_STAGES.map(s => [s.key, bom[s.key] ?? ''])),
    rows: (bom.bomItems || []).map(it => ({
      id: it.id,
      materialNo: it.materialNo || '',
      materialName: it.materialName || '',
      specification: it.specification || '',
      unit: it.unit || '',
      qty: String(it.qty ?? ''),
      remark: it.remark || '',
    })),
  });
  dialogRef.value?.open();
};

// targetStatus：'DRAFT' 存草稿 / 'RELEASED' 下发。
const submit = async targetStatus => {
  if (invalid.value) return;
  const itemsAttributes = [
    ...form.rows.map(r => ({
      id: r.id || undefined,
      materialNo: r.materialNo.trim(),
      materialName: r.materialName.trim(),
      specification: r.specification.trim(),
      unit: r.unit.trim(),
      qty: Number(r.qty),
      remark: r.remark.trim(),
    })),
    ...removedItemIds.value.map(id => ({ id, _destroy: true })),
  ];
  const payload = {
    crmProductId: form.crmProductId || null,
    baseQty: Number(form.baseQty) || 1,
    unit: form.unit,
    status: targetStatus,
    ...Object.fromEntries(
      LEAD_STAGES.map(s => [s.key, Number(form[s.key]) || null])
    ),
    bomItemsAttributes: itemsAttributes,
  };
  const ok = editingId.value
    ? await store.update({ id: editingId.value, ...payload })
    : await store.create(payload);
  if (ok) {
    const verb = targetStatus === 'RELEASED' ? '已下发' : '已存草稿';
    useAlert(editingId.value ? `BOM ${verb}` : `${verb} ${ok.bomNo}`);
    dialogRef.value?.close();
  }
};

// 列表里把草稿一键下发。
const release = async bom => {
  releasingId.value = bom.id;
  try {
    await MesBomAPI.release(bom.id);
    await store.get();
    useAlert(`已下发 ${bom.bomNo}`);
  } catch {
    useAlert('下发失败');
  } finally {
    releasingId.value = null;
  }
};

onMounted(async () => {
  store.get();
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/products`
    );
    products.value = data?.payload || data || [];
  } catch {
    products.value = [];
  }
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-6 py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">工程/PMC BOM</h1>
      <Button
        v-if="mesCan('bom')"
        label="新建 BOM"
        color="iris"
        size="sm"
        @click="openCreate"
      />
    </div>

    <MesBoardOwnerBar board-key="mes_boms_index" />

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-3 font-medium">BOM 号</th>
            <th class="px-3 py-3 font-medium">成品</th>
            <th class="px-3 py-3 font-medium">基准产量</th>
            <th class="px-3 py-3 font-medium">用料项</th>
            <th class="px-3 py-3 font-medium">预估周期(天)</th>
            <th class="px-3 py-3 font-medium">状态</th>
            <th class="px-3 py-3" />
          </tr>
        </thead>
        <tbody>
          <tr v-for="b in records" :key="b.id" class="border-b border-n-weak">
            <td class="px-3 py-3 font-medium text-n-slate-12">{{ b.bomNo }}</td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ b.productName || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ b.baseQty }} {{ b.unit }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ (b.bomItems || []).length }} 项
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ b.totalLeadDays || '—' }}
            </td>
            <td class="px-3 py-3">
              <span
                class="px-2 py-0.5 text-xs rounded-full"
                :class="
                  b.status === 'RELEASED'
                    ? 'bg-n-teal-3 text-n-teal-12'
                    : 'bg-n-slate-4 text-n-slate-11'
                "
              >
                {{ b.status === 'RELEASED' ? '已下发' : '草稿' }}
              </span>
            </td>
            <td class="px-3 py-3 text-right">
              <div class="flex justify-end gap-1">
                <Button
                  v-if="mesCan('bom') && b.status !== 'RELEASED'"
                  label="下发"
                  color="iris"
                  size="sm"
                  :is-loading="releasingId === b.id"
                  @click="release(b)"
                />
                <Button
                  v-if="mesCan('bom')"
                  label="编辑"
                  variant="ghost"
                  size="sm"
                  @click="openEdit(b)"
                />
              </div>
            </td>
          </tr>
          <tr v-if="!records.length">
            <td colspan="7" class="px-3 py-10 text-center text-n-slate-11">
              还没有 BOM。
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog
      ref="dialogRef"
      width="3xl"
      overflow-y-auto
      :show-confirm-button="false"
      :show-cancel-button="false"
      :title="editingId ? '编辑 BOM' : '新建 BOM'"
      :is-loading="saving"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">成品</label>
            <ComboBox
              v-model="form.crmProductId"
              :options="productOptions"
              placeholder="选择成品"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12"
              >基准产量 / 单位</label
            >
            <div class="flex gap-2">
              <Input v-model="form.baseQty" type="number" class="w-20" />
              <Input v-model="form.unit" placeholder="台" />
            </div>
          </div>
        </div>

        <div class="flex flex-col gap-2">
          <div class="flex items-center justify-between">
            <span class="text-heading-3 text-n-slate-12">各阶段预估天数</span>
            <span class="text-xs text-n-slate-11">
              预估周期合计：<span class="font-medium text-n-slate-12">{{
                totalLeadDays
              }}</span>
              天
            </span>
          </div>
          <div class="grid grid-cols-5 gap-2">
            <div
              v-for="s in LEAD_STAGES"
              :key="s.key"
              class="flex flex-col gap-1"
            >
              <label class="text-xs text-n-slate-11">{{ s.label }}</label>
              <Input v-model="form[s.key]" type="number" placeholder="天" />
            </div>
          </div>
        </div>

        <div
          class="flex items-center justify-between pt-2 border-t border-n-weak"
        >
          <span class="text-heading-3 text-n-slate-12">
            用料明细 <span class="text-n-ruby-11">*</span>
          </span>
          <Button label="+ 加一行" variant="ghost" size="sm" @click="addRow" />
        </div>

        <div class="flex flex-col gap-2">
          <div class="grid grid-cols-12 gap-2 px-1 text-xs text-n-slate-11">
            <span class="col-span-2">物料编码</span>
            <span class="col-span-3"
              >物料名称 <span class="text-n-ruby-11">*</span></span
            >
            <span class="col-span-2">规格型号</span>
            <span class="col-span-1">单位</span>
            <span class="col-span-1"
              >用量 <span class="text-n-ruby-11">*</span></span
            >
            <span class="col-span-2">备注</span>
            <span class="col-span-1" />
          </div>
          <div
            v-for="(row, i) in form.rows"
            :key="i"
            class="grid items-center grid-cols-12 gap-2"
          >
            <Input
              v-model="row.materialNo"
              placeholder="P.03.201"
              class="col-span-2"
            />
            <Input
              v-model="row.materialName"
              placeholder="P30主板"
              class="col-span-3"
            />
            <Input
              v-model="row.specification"
              placeholder="规格型号"
              class="col-span-2"
            />
            <Input v-model="row.unit" placeholder="台" class="col-span-1" />
            <Input
              v-model="row.qty"
              type="number"
              placeholder="用量"
              class="col-span-1"
            />
            <Input v-model="row.remark" placeholder="备注" class="col-span-2" />
            <button
              type="button"
              class="col-span-1 text-n-slate-10 hover:text-n-ruby-11"
              @click="removeRow(i)"
            >
              ✕
            </button>
          </div>
        </div>
      </div>

      <template #footer>
        <div class="flex justify-end gap-2">
          <Button
            label="取消"
            variant="ghost"
            color="slate"
            @click="dialogRef?.close()"
          />
          <!-- 已下发的编辑：只保留「保存」，保持已下发 -->
          <Button
            v-if="editingId && editingStatus === 'RELEASED'"
            label="保存"
            color="iris"
            :is-loading="saving"
            :disabled="invalid"
            @click="submit('RELEASED')"
          />
          <template v-else>
            <Button
              label="存草稿"
              variant="outline"
              color="slate"
              :is-loading="saving"
              :disabled="invalid"
              @click="submit('DRAFT')"
            />
            <Button
              label="下发"
              color="iris"
              :is-loading="saving"
              :disabled="invalid"
              @click="submit('RELEASED')"
            />
          </template>
        </div>
      </template>
    </Dialog>
  </div>
</template>
