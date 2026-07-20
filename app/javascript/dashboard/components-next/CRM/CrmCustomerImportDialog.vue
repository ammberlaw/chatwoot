<script setup>
/**
 * 客户批量导入向导（管理层）：三步——
 *   1. 上传 .xlsx/.csv，浏览器用 SheetJS 解析出列头+数据；
 *   2. 字段映射：每个源列选一个 CRM 字段（按列名自动猜，可手动改）；
 *   3. 提交 → 后端归一化中文枚举 + 查重建档 + 建联系人，回显逐行结果。
 * 从小满等外部 CRM 导出的表列名/取值各异，映射在前端做，取值归一在后端做。
 */
import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import * as XLSX from 'xlsx';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmCustomerAPI from 'dashboard/api/crm/customers';

defineProps({
  // [{ value, label }]：可指派的负责人（本人+辖区成员），空值=未分配。
  memberOptions: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['imported']);

const dialogRef = ref(null);
const step = ref('upload'); // upload | mapping | result
const fileName = ref('');
const headers = ref([]); // 源表列头
const dataRows = ref([]); // 源表数据行（数组的数组）
const columnMap = ref({}); // { 源列名: CRM字段key | '' }
const defaultOwnerId = ref('');
const importing = ref(false);
const summary = ref(null);

// 可映射的目标字段。enum 字段的中文取值归一在后端处理。
const TARGET_FIELDS = [
  { key: 'name', label: '公司名称（必填）' },
  { key: 'customer_code', label: '客户编号' },
  { key: 'website', label: '网址 / 域名' },
  { key: 'trade_country', label: '国家' },
  { key: 'trade_region', label: '地区' },
  { key: 'trade_city', label: '城市' },
  { key: 'address', label: '地址' },
  { key: 'industry', label: '行业' },
  { key: 'customer_level', label: '客户等级' },
  { key: 'source_channel', label: '客户来源' },
  { key: 'customer_status', label: '客户状态' },
  { key: 'currency_preference', label: '币种偏好' },
  { key: 'customer_group', label: '客户分组' },
  { key: 'product_group', label: '产品分组' },
  { key: 'customer_remark', label: '备注' },
  { key: 'linkedin', label: 'LinkedIn' },
  { key: 'whats_app', label: 'WhatsApp' },
  { key: 'wechat', label: '微信' },
  { key: 'contact_name', label: '联系人姓名' },
  { key: 'contact_job_title', label: '联系人职位' },
  { key: 'contact_email', label: '联系人邮箱' },
  { key: 'contact_phone', label: '联系人电话' },
  { key: 'contact_preference', label: '联系偏好' },
];

// 列名 → 字段key 的自动猜测：命中任一关键词即映射。
const GUESS = [
  ['name', ['公司', '客户名', '企业名', 'company', 'customer name', '名称']],
  ['customer_code', ['编号', '编码', 'code', '客户id']],
  ['website', ['网址', '网站', '域名', 'website', 'url', 'web']],
  ['trade_country', ['国家', 'country', '国别']],
  ['trade_region', ['地区', '区域', '大洲', 'region']],
  ['trade_city', ['城市', 'city']],
  ['address', ['地址', 'address', '详细地址']],
  ['industry', ['行业', 'industry']],
  ['customer_level', ['等级', '级别', 'level', '星级']],
  ['source_channel', ['来源', '渠道', 'source', 'channel']],
  ['customer_status', ['状态', 'status', '阶段']],
  ['currency_preference', ['币种', '货币', 'currency']],
  ['customer_group', ['分组', '客户组']],
  ['product_group', ['产品', 'product']],
  ['customer_remark', ['备注', '说明', 'remark', 'note', '描述']],
  ['linkedin', ['linkedin', '领英']],
  ['whats_app', ['whatsapp', 'whats app']],
  ['wechat', ['微信', 'wechat']],
  ['contact_email', ['邮箱', 'email', 'e-mail', '电子邮件']],
  ['contact_phone', ['电话', '手机', 'phone', 'tel', 'mobile', '联系方式']],
  ['contact_job_title', ['职位', '职务', 'title', 'position']],
  ['contact_name', ['联系人', 'contact', '姓名']],
  ['contact_preference', ['联系偏好', '偏好']],
];

const guessField = header => {
  const h = String(header).toLowerCase().trim();
  const hit = GUESS.find(([, kws]) => kws.some(kw => h.includes(kw)));
  return hit ? hit[0] : '';
};

const nameMapped = computed(() =>
  Object.values(columnMap.value).includes('name')
);

const mappedCount = computed(
  () => Object.values(columnMap.value).filter(Boolean).length
);

const open = () => {
  step.value = 'upload';
  fileName.value = '';
  headers.value = [];
  dataRows.value = [];
  columnMap.value = {};
  defaultOwnerId.value = '';
  summary.value = null;
  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();

const onFile = async e => {
  const file = e.target.files?.[0];
  if (!file) return;
  try {
    fileName.value = file.name;
    const buf = await file.arrayBuffer();
    const wb = XLSX.read(buf, { type: 'array' });
    const ws = wb.Sheets[wb.SheetNames[0]];
    // header:1 → 数组的数组；raw:false 让日期/数字转成显示文本；defval 补空串
    const matrix = XLSX.utils.sheet_to_json(ws, {
      header: 1,
      raw: false,
      defval: '',
      blankrows: false,
    });
    if (!matrix.length) {
      useAlert('文件里没有读到数据');
      return;
    }
    const rawHeaders = matrix[0].map(h => String(h).trim());
    headers.value = rawHeaders;
    dataRows.value = matrix
      .slice(1)
      .filter(r => r.some(c => String(c).trim() !== ''));
    // 自动猜测映射；同一字段被多列命中时只保留第一个
    const used = new Set();
    const map = {};
    rawHeaders.forEach(h => {
      const g = guessField(h);
      if (g && !used.has(g)) {
        map[h] = g;
        used.add(g);
      } else {
        map[h] = '';
      }
    });
    columnMap.value = map;
    step.value = 'mapping';
  } catch (err) {
    useAlert('解析失败，请确认是 Excel(.xlsx) 或 CSV 文件');
  } finally {
    e.target.value = '';
  }
};

// 组装成后端要的行：{ 字段key: 值 }，跳过没映射到任何字段的列与空行。
const buildRows = () => {
  const cols = headers.value
    .map((h, i) => ({ i, field: columnMap.value[h] }))
    .filter(c => c.field);
  return dataRows.value
    .map(row => {
      const obj = {};
      cols.forEach(({ i, field }) => {
        const v = String(row[i] ?? '').trim();
        if (v) obj[field] = v;
      });
      return obj;
    })
    .filter(o => Object.keys(o).length);
};

const doImport = async () => {
  if (!nameMapped.value) {
    useAlert('请先把「公司名称」映射到某一列');
    return;
  }
  const rows = buildRows();
  if (!rows.length) {
    useAlert('没有可导入的数据行');
    return;
  }
  importing.value = true;
  try {
    const { data } = await CrmCustomerAPI.import({
      rows,
      defaultOwnerId: defaultOwnerId.value,
    });
    summary.value = data;
    step.value = 'result';
    emit('imported');
  } catch (err) {
    useAlert(err?.response?.data?.error || '导入失败');
  } finally {
    importing.value = false;
  }
};

const failedRows = computed(
  () => summary.value?.results?.filter(r => r.status === 'failed') || []
);
const warnRows = computed(
  () =>
    summary.value?.results?.filter(
      r => r.status === 'created' && r.warnings?.length
    ) || []
);

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    overflow-y-auto
    :show-cancel-button="false"
    :show-confirm-button="false"
  >
    <div class="flex flex-col gap-5">
      <div class="flex items-center justify-between">
        <span class="text-base font-medium text-n-slate-12">批量导入客户</span>
        <span class="text-xs text-n-slate-10">
          支持 Excel(.xlsx) / CSV，可从小满导出后直接上传
        </span>
      </div>

      <!-- 步骤 1：上传 -->
      <div v-if="step === 'upload'" class="flex flex-col gap-4">
        <label
          class="flex flex-col items-center justify-center gap-2 px-6 py-10 text-sm transition-colors border border-dashed rounded-xl cursor-pointer border-n-weak text-n-slate-11 hover:border-n-iris-9 hover:text-n-iris-11"
        >
          <span class="i-lucide-upload-cloud text-2xl" />
          <span>点击选择文件，或拖拽 Excel / CSV 到此处</span>
          <input
            type="file"
            accept=".xlsx,.xls,.csv"
            class="hidden"
            @change="onFile"
          />
        </label>
        <ul class="pl-4 text-xs list-disc text-n-slate-10">
          <li>第一行需为列标题（公司名称、国家、邮箱…）。</li>
          <li>
            国家/来源/等级等中文值系统会自动转成标准值，识别不了的会在结果里标出。
          </li>
          <li>同名公司已存在会自动跳过，不会重复建档。</li>
        </ul>
      </div>

      <!-- 步骤 2：字段映射 -->
      <div v-else-if="step === 'mapping'" class="flex flex-col gap-4">
        <div class="flex items-center justify-between text-sm">
          <span class="text-n-slate-11">
            已读取
            <b class="text-n-slate-12">{{ dataRows.length }}</b>
            行 · 文件 {{ fileName }}
          </span>
          <span :class="nameMapped ? 'text-n-teal-11' : 'text-n-ruby-11'">
            {{
              nameMapped ? `已映射 ${mappedCount} 列` : '⚠ 请映射「公司名称」'
            }}
          </span>
        </div>

        <div class="overflow-y-auto border rounded-lg max-h-72 border-n-weak">
          <table class="w-full text-sm">
            <thead
              class="sticky top-0 text-xs text-left bg-n-alpha-2 text-n-slate-10"
            >
              <tr>
                <th class="px-3 py-2 font-medium">源列（表头）</th>
                <th class="px-3 py-2 font-medium">示例值</th>
                <th class="px-3 py-2 font-medium">导入到 CRM 字段</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(h, idx) in headers"
                :key="idx"
                class="border-t border-n-weak"
              >
                <td class="px-3 py-2 text-n-slate-12">{{ h || '(空列)' }}</td>
                <td class="px-3 py-2 truncate max-w-[10rem] text-n-slate-10">
                  {{ dataRows[0]?.[idx] }}
                </td>
                <td class="px-3 py-2">
                  <select
                    v-model="columnMap[h]"
                    class="h-8 px-2 text-sm border rounded-md w-52 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-9"
                  >
                    <option value="">— 不导入 —</option>
                    <option
                      v-for="f in TARGET_FIELDS"
                      :key="f.key"
                      :value="f.key"
                    >
                      {{ f.label }}
                    </option>
                  </select>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="flex items-center gap-3">
          <label class="text-sm text-n-slate-11">导入后负责人</label>
          <select
            v-model="defaultOwnerId"
            class="h-8 px-2 text-sm border rounded-md w-52 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-9"
          >
            <option value="">未分配</option>
            <option
              v-for="m in memberOptions.filter(o => o.value)"
              :key="m.value"
              :value="m.value"
            >
              {{ m.label }}
            </option>
          </select>
        </div>
      </div>

      <!-- 步骤 3：结果 -->
      <div v-else class="flex flex-col gap-4">
        <div class="grid grid-cols-3 gap-3 text-center">
          <div class="px-3 py-4 rounded-lg bg-n-teal-3">
            <div class="text-2xl font-semibold text-n-teal-11">
              {{ summary.created }}
            </div>
            <div class="text-xs text-n-slate-11">新建成功</div>
          </div>
          <div class="px-3 py-4 rounded-lg bg-n-amber-3">
            <div class="text-2xl font-semibold text-n-amber-11">
              {{ summary.skipped }}
            </div>
            <div class="text-xs text-n-slate-11">跳过（已存在）</div>
          </div>
          <div class="px-3 py-4 rounded-lg bg-n-ruby-3">
            <div class="text-2xl font-semibold text-n-ruby-11">
              {{ summary.failed }}
            </div>
            <div class="text-xs text-n-slate-11">失败</div>
          </div>
        </div>

        <div v-if="failedRows.length" class="overflow-y-auto text-sm max-h-40">
          <div class="mb-1 font-medium text-n-ruby-11">失败明细</div>
          <ul class="pl-4 list-disc text-n-slate-11">
            <li v-for="r in failedRows" :key="`f${r.row}`">
              第 {{ r.row }} 行「{{ r.name }}」：{{ r.message }}
            </li>
          </ul>
        </div>

        <div v-if="warnRows.length" class="overflow-y-auto text-sm max-h-40">
          <div class="mb-1 font-medium text-n-amber-11">
            以下已导入，但有值需要复核
          </div>
          <ul class="pl-4 list-disc text-n-slate-11">
            <li v-for="r in warnRows" :key="`w${r.row}`">
              第 {{ r.row }} 行「{{ r.name }}」：{{ r.warnings.join('；') }}
            </li>
          </ul>
        </div>
      </div>
    </div>

    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          variant="faded"
          color="slate"
          :label="step === 'result' ? '关闭' : '取消'"
          type="button"
          @click="close"
        />
        <Button
          v-if="step === 'mapping'"
          label="开始导入"
          color="iris"
          type="button"
          :is-loading="importing"
          :disabled="!nameMapped || importing"
          @click="doImport"
        />
        <Button
          v-else-if="step === 'result'"
          label="完成"
          color="iris"
          type="button"
          @click="close"
        />
      </div>
    </template>
  </Dialog>
</template>
