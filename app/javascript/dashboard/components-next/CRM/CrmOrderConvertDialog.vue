<script setup>
import { ref, reactive, computed, nextTick } from 'vue';
import { useAlert } from 'dashboard/composables';
import SalesOrdersAPI from 'dashboard/api/crm/salesOrders';
import MesProductAPI from 'dashboard/api/mes/products';
import MesWarehouseAPI from 'dashboard/api/mes/warehouses';
import MesProductionOrderAPI from 'dashboard/api/mes/productionOrders';
import MesShipmentAPI from 'dashboard/api/mes/shipments';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

// 销售订单一键转下游单据。业务员录一次订单，不用去 MES 再敲一遍客户/产品/数量。
//   定制单 → 生产订单（每行明细各转一张，都挂回同一张销售订单；
//            有 :order 能力直接生效，业务员等 CRM 角色转的进审批链）
//   库存单 → 现货出库单（提交即预占成品库存，走主管审核）
// 销售订单明细是自由文本（PI 识别填的），下游要产品档案 ID 才能扣库存/带 BOM，
// 所以这里按名称匹配一次，匹配不上的行让业务员选一次。
const emit = defineEmits(['converted']);

const dialogRef = ref(null);
const order = ref(null);
const kind = ref('');
const submitting = ref(false);
const products = ref([]);
const warehouses = ref([]);
const warehouseId = ref('');
// 转单备注：写给下游（生产/仓管）看的交代。定制单每行各一张生产订单，都带同一份；
// 出库单接在「由销售订单 X 转入」后面，出处那行保留。
const remark = ref('');
// [{ name, qty, unit, productId, convertedOrderNo }]
const rows = reactive([]);

const KIND_OPTIONS = [
  { value: 'CUSTOM', label: '定制单 → 生产订单' },
  { value: 'STOCK', label: '库存单 → 现货出库单' },
];

// 下拉要带规格：同一个型号常有七八个商品编码（K717 外贸/迪拜、1+8G/1+16G、9832/6735、
// 欧规/英规），只给「名称（编码）」七行长得一模一样，根本选不出该转哪个
// （2026-10-29 反馈）。区分它们的信息全在规格里。
const productOptions = computed(() =>
  products.value.map(p => ({
    value: p.id,
    label: [p.name, p.specification].filter(Boolean).join(' · ') +
      (p.sku ? `（${p.sku}）` : ''),
  }))
);

// 搜过的产品留一份底，按 id 存。
//
// ⚠️ 这份底是必须的：ComboBox 选中时只回传 value，拿不到整条产品记录，
// 而每次远程搜索都会把 products 整个换掉。原来只把 row.product 并回去，
// 可 row.product 只在打开弹窗、后端已匹配到产品时才有值——用户自己从下拉里
// 选的那几行它一直是 null。于是选完第一行、再搜第二个编码时，第一行选中的
// 那条已经不在候选里，下拉找不到对应项，**看起来就是前面选的全被清掉**。
// （2026-10-30 金蝶外贸单转单，一张单四五个编码，选第二个时前面全没了。）
const seenProducts = new Map();

const rememberProducts = list => {
  list.forEach(p => {
    if (p?.id) seenProducts.set(p.id, p);
  });
};

// 产品档案上千条，不预载——下拉按关键词远程搜，已选中的并进选项里保持回显。
const searchProducts = async q => {
  const { data } = await MesProductAPI.get({ q, per_page: 30 });
  const found = data?.payload || [];
  rememberProducts(found);
  const merged = [...found];
  rows.forEach(r => {
    const picked = seenProducts.get(r.productId);
    if (picked && !merged.some(m => m.id === picked.id)) merged.push(picked);
  });
  products.value = merged;
};

const unmatchedCount = computed(
  () => rows.filter(r => !r.convertedOrderNo && !r.productId).length
);
// 已转过的行不参与本次提交（后端也按「销售订单+产品」跳过，这里只是不让人白填）。
const pendingRows = computed(() => rows.filter(r => !r.convertedOrderNo));
const convertedCount = computed(() => rows.length - pendingRows.value.length);
const canSubmit = computed(
  () =>
    !!kind.value &&
    pendingRows.value.length > 0 &&
    pendingRows.value.every(r => r.productId && Number(r.qty) > 0) &&
    (kind.value !== 'STOCK' || !!warehouseId.value)
);

// 订单金额含不含税：同一家公司两种合同都有，所以不在账套上一刀切，转单时当场勾。
// 决定出库收入凭证怎么拆：含税 → 收入=金额÷(1+税率)、应收=金额；
// 不含税 → 收入=金额、应收=金额+税额。税率 0 的出口单两种算法同值，不影响。
const includesTax = ref(true);
const taxRate = computed(() => Number(order.value?.taxRate ?? 0));

const open = async record => {
  order.value = record;
  kind.value = record.orderKind || '';
  // 单据上记过就沿用，没记过默认含税（国内合同惯例）。
  includesTax.value = record.amountIncludesTax ?? true;
  warehouseId.value = '';
  remark.value = '';
  rows.splice(0, rows.length);
  dialogRef.value?.open();

  // 明细→产品档案的匹配放后端（SQL 比前端拉一页回来匹配准得多）。
  const [previewRes, whRes] = await Promise.all([
    SalesOrdersAPI.convertPreview(record.id),
    MesWarehouseAPI.get(),
  ]);
  warehouses.value = whRes.data?.payload || [];
  if (warehouses.value.length === 1) warehouseId.value = warehouses.value[0].id;

  (previewRes.data?.payload || []).forEach(li => {
    const product = li.crm_product_id
      ? {
          id: li.crm_product_id,
          name: li.product_name,
          sku: li.product_sku,
          // 后端 Crm::ConvertPreview 本来就给了 product_spec，不带上的话
          // 已匹配那行的回显没有规格，和下拉里的其它项对不上。
          specification: li.product_spec,
        }
      : null;
    rows.push({
      // row = 明细行号（1 起），提交时回传：后端据此把选中的产品写回销售订单明细，
      // 并记进别名记忆，下次同样的客户叫法自动命中，不用再搜一遍产品档案。
      row: li.row,
      name: li.name || '',
      qty: li.quantity ?? '',
      unit: li.unit || '',
      productId: li.crm_product_id || '',
      product,
      convertedOrderNo: li.converted_order_no || '',
    });
  });
  // 已匹配到的产品先进选项，下拉不搜也能回显名字；同时进底库，后面搜别的行不会把它挤掉。
  const matched = rows.map(r => r.product).filter(Boolean);
  rememberProducts(matched);
  products.value = matched;
  // 明细为空的订单（老单/没填明细）给一行空的，手动选产品填数量也能转。
  if (!rows.length)
    rows.push({
      name: '',
      qty: '',
      unit: '',
      productId: '',
      product: null,
      convertedOrderNo: '',
    });
  await nextTick();
};

const addRow = () =>
  rows.push({
    name: '',
    qty: '',
    unit: '',
    productId: '',
    product: null,
    convertedOrderNo: '',
  });
const removeRow = i => rows.splice(i, 1);

const submitCustom = async () => {
  // 生产脊柱按成品走：一行明细一张生产订单，全部挂回这张销售订单。
  const { data } = await MesProductionOrderAPI.convert({
    crm_sales_order_id: order.value.id,
    amount_includes_tax: includesTax.value,
    remark: remark.value.trim() || undefined,
    items: pendingRows.value.map(r => ({
      crm_product_id: r.productId,
      qty: r.qty,
      unit: r.unit || undefined,
      row: r.row,
    })),
  });
  const nos = (data.order_nos || []).join('、');
  const skipped = data.skipped ? `（另 ${data.skipped} 行此前已转）` : '';
  return `已生成生产订单 ${nos}${skipped}`.trim();
};

const submitStock = async () => {
  const { data } = await MesShipmentAPI.convert({
    crm_sales_order_id: order.value.id,
    warehouse_id: warehouseId.value,
    amount_includes_tax: includesTax.value,
    remark: remark.value.trim() || undefined,
    items: rows.map(r => ({
      crm_product_id: r.productId,
      qty: r.qty,
      unit: r.unit || undefined,
      row: r.row,
    })),
  });
  return `已生成出库单 ${data.shipment_no || ''}，等待主管审核`.trim();
};

const submit = async () => {
  if (!canSubmit.value || submitting.value) return;
  submitting.value = true;
  try {
    const msg =
      kind.value === 'STOCK' ? await submitStock() : await submitCustom();
    useAlert(msg);
    dialogRef.value?.close();
    emit('converted');
  } catch (e) {
    useAlert(e?.response?.data?.error || '转单失败');
  } finally {
    submitting.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    title="转单"
    :show-confirm-button="false"
    :show-cancel-button="false"
  >
    <div v-if="order" class="flex flex-col gap-4">
      <div class="text-sm text-n-slate-11">
        销售订单
        <span class="font-medium text-n-slate-12">{{ order.orderNo }}</span>
        · {{ order.customerName || '未指定客户' }}
      </div>

      <div class="grid grid-cols-2 gap-4">
        <div class="flex flex-col min-w-0 gap-1">
          <label class="text-heading-3 text-n-slate-12">
            转订单类型
            <span class="text-n-ruby-11">*</span>
          </label>
          <SelectCard v-model="kind" block :options="KIND_OPTIONS" />
        </div>
        <div v-if="kind === 'STOCK'" class="flex flex-col min-w-0 gap-1">
          <label class="text-heading-3 text-n-slate-12">出库仓库</label>
          <SelectCard
            v-model="warehouseId"
            block
            :options="warehouses.map(w => ({ value: w.id, label: w.name }))"
          />
        </div>
      </div>

      <!-- 订单金额含不含税：决定出库后那张收入凭证怎么拆行。税率 0 的出口单不影响。 -->
      <div class="flex flex-col gap-1">
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <input v-model="includesTax" type="checkbox" class="w-4 h-4" />
          订单金额已含税
        </label>
        <p v-if="taxRate > 0" class="text-xs text-n-slate-11">
          税率 {{ taxRate }}%。勾上＝金额里已经含了税，收入按 金额÷(1+税率)
          确认、应收等于金额；不勾＝金额是不含税价，税额另加，应收 = 金额 +
          税额。
        </p>
      </div>

      <div class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <span class="text-heading-3 text-n-slate-12">
            明细
            <span v-if="unmatchedCount" class="text-n-amber-11">
              （有 {{ unmatchedCount }} 行没匹配到产品档案，请手动选）
            </span>
          </span>
          <button
            type="button"
            class="h-8 px-3 text-sm border rounded-lg border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            @click="addRow"
          >
            加一行
          </button>
        </div>
        <div class="flex items-center gap-2 px-1 text-xs text-n-slate-10">
          <span class="flex-[3]">订单上的品名</span>
          <span class="flex-[3]">
            商品编码
            <span class="text-n-ruby-11">*</span>
          </span>
          <span class="flex-1">数量</span>
          <span class="flex-1">单位</span>
          <span class="w-6 shrink-0" />
        </div>
        <div
          v-for="(row, index) in rows"
          :key="index"
          class="flex items-center gap-2"
          :class="{ 'opacity-55': row.convertedOrderNo }"
        >
          <span class="flex-[3] text-sm truncate text-n-slate-11">
            {{ row.name || '—' }}
          </span>
          <ComboBox
            v-model="row.productId"
            class="flex-[3]"
            :options="productOptions"
            :disabled="!!row.convertedOrderNo"
            placeholder="搜索产品名称 / SKU"
            use-api-results
            @search="searchProducts"
          />
          <Input
            v-model="row.qty"
            type="number"
            class="flex-1"
            :disabled="!!row.convertedOrderNo"
          />
          <Input
            v-model="row.unit"
            class="flex-1"
            :disabled="!!row.convertedOrderNo"
          />
          <button
            type="button"
            class="flex items-center justify-center w-6 shrink-0 text-n-slate-10 hover:text-n-ruby-11"
            @click="removeRow(index)"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>
      </div>

      <span v-if="convertedCount > 0" class="text-xs text-n-slate-11">
        灰掉的 {{ convertedCount }} 行此前已转过，本次只转其余
        {{ pendingRows.length }} 行。
      </span>
      <span
        v-else-if="kind === 'CUSTOM' && pendingRows.length > 1"
        class="text-xs text-n-slate-11"
      >
        生产订单一单一个成品，这 {{ pendingRows.length }}
        行会各生成一张生产订单，都挂在这张销售订单下。
      </span>

      <span v-if="unmatchedCount" class="text-xs text-n-ruby-11">
        还有 {{ unmatchedCount }} 行没选商品编码，选齐才能转单{{
          kind === 'STOCK' ? '——现货出库要按编码扣库存' : ''
        }}。
      </span>

      <div class="flex flex-col gap-1">
        <label class="text-heading-3 text-n-slate-12">备注</label>
        <TextArea v-model="remark" :rows="2" />
      </div>

      <div class="flex justify-end gap-2 pt-1">
        <button
          type="button"
          class="h-9 px-4 text-sm font-medium border rounded-lg border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
          @click="dialogRef?.close()"
        >
          取消
        </button>
        <button
          type="button"
          class="h-9 px-4 text-sm font-medium text-white rounded-lg bg-gradient-to-br from-n-iris-9 to-n-accent-grad hover:brightness-105 disabled:opacity-50"
          :disabled="!canSubmit || submitting"
          @click="submit"
        >
          {{ submitting ? '转单中…' : '确认转单' }}
        </button>
      </div>
    </div>
  </Dialog>
</template>
