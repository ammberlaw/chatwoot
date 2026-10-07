<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import camelcaseKeys from 'camelcase-keys';
import QuoteRequestTemplatesAPI from 'dashboard/api/crm/quoteRequestTemplates';
import { isClassicTheme } from 'dashboard/components-next/CRM/charts/chartColors';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

// 定制报价的参数模板：每条产品线配一套字段，业务员发起申请时按产品线套用。
// 字段定义结构与 OA 审批模板一致（key/label/type/required/options），前端渲染逻辑同源。
const isClassic = ref(isClassicTheme());
const goColor = computed(() => (isClassic.value ? 'amber' : 'teal'));

const FIELD_TYPES = [
  { value: 'text', label: '单行文本' },
  { value: 'number', label: '数字' },
  { value: 'textarea', label: '多行文本' },
  { value: 'select', label: '下拉选择' },
  { value: 'date', label: '日期' },
];

const rows = ref([]);
const loading = ref(true);
const saving = ref(false);
const dialogRef = ref(null);
const editing = ref(null);
const form = ref({
  productLine: '',
  name: '',
  description: '',
  active: true,
  fields: [],
});
const { isDirty, markPristine } = useDirtyGuard(() => form.value);

const load = async () => {
  loading.value = true;
  try {
    const { data } = await QuoteRequestTemplatesAPI.get();
    rows.value = camelcaseKeys(data.payload || [], { deep: true });
  } catch (error) {
    useAlert(error?.response?.data?.error || '加载失败');
  } finally {
    loading.value = false;
  }
};

const openNew = () => {
  editing.value = null;
  form.value = {
    productLine: '',
    name: '',
    description: '',
    active: true,
    fields: [],
  };
  markPristine();
  dialogRef.value?.open();
};

const openEdit = row => {
  editing.value = row;
  form.value = {
    productLine: row.productLine,
    name: row.name,
    description: row.description || '',
    active: row.active,
    // 下拉选项在表单里用逗号分隔的字符串编辑，提交时再切回数组。
    fields: (row.formFields || []).map(f => ({
      key: f.key,
      label: f.label,
      type: f.type,
      required: Boolean(f.required),
      optionsText: (f.options || []).join('，'),
    })),
  };
  markPristine();
  dialogRef.value?.open();
};

const addField = () => {
  form.value.fields.push({
    key: '',
    label: '',
    type: 'text',
    required: false,
    optionsText: '',
  });
};
const removeField = i => {
  form.value.fields.splice(i, 1);
};
const moveField = (i, dir) => {
  const j = i + dir;
  if (j < 0 || j >= form.value.fields.length) return;
  const arr = form.value.fields;
  [arr[i], arr[j]] = [arr[j], arr[i]];
};

const save = async () => {
  if (!form.value.productLine.trim() || !form.value.name.trim()) {
    useAlert('请填写产品线和模板名称');
    return;
  }
  const bad = form.value.fields.find(f => !f.key.trim() || !f.label.trim());
  if (bad) {
    useAlert('每个字段都要填「字段名」和「显示名」');
    return;
  }
  const dupKey = form.value.fields
    .map(f => f.key.trim())
    .find((k, i, arr) => arr.indexOf(k) !== i);
  if (dupKey) {
    useAlert(`字段名「${dupKey}」重复了`);
    return;
  }

  saving.value = true;
  try {
    const payload = {
      template: {
        product_line: form.value.productLine.trim(),
        name: form.value.name.trim(),
        description: form.value.description.trim(),
        active: form.value.active,
        form_fields: form.value.fields.map(f => ({
          key: f.key.trim(),
          label: f.label.trim(),
          type: f.type,
          required: f.required,
          options:
            f.type === 'select'
              ? f.optionsText
                  .split(/[，,]/)
                  .map(s => s.trim())
                  .filter(Boolean)
              : [],
        })),
      },
    };
    if (editing.value)
      await QuoteRequestTemplatesAPI.update(editing.value.id, payload);
    else await QuoteRequestTemplatesAPI.create(payload);
    dialogRef.value?.close();
    useAlert(editing.value ? '已保存' : '模板已创建');
    load();
  } catch (error) {
    useAlert(error?.response?.data?.error || '保存失败');
  } finally {
    saving.value = false;
  }
};

const remove = async row => {
  try {
    await QuoteRequestTemplatesAPI.delete(row.id);
    useAlert('已删除');
    load();
  } catch (error) {
    useAlert(error?.response?.data?.error || '删除失败');
  }
};

const typeLabel = t => FIELD_TYPES.find(x => x.value === t)?.label || t;

onMounted(load);
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div class="w-full px-4 py-4 mx-auto max-w-5xl sm:px-8 sm:py-6">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h1 class="text-[22px] font-bold tracking-[-0.01em] text-n-slate-12">
          定制报价模板
        </h1>
        <Button
          label="新建模板"
          icon="i-lucide-plus"
          :color="goColor"
          size="sm"
          @click="openNew"
        />
      </div>
      <p class="mt-1 mb-5 text-sm text-n-slate-11">
        每条产品线配一套参数字段。业务员发起定制报价时选产品线，这里配的字段就会出现在表单里。
      </p>

      <p v-if="loading" class="py-8 text-sm text-center text-n-slate-10">
        加载中…
      </p>
      <p
        v-else-if="!rows.length"
        class="py-10 text-sm text-center text-n-slate-10"
      >
        还没有模板。点「新建模板」给第一条产品线配上参数。
      </p>

      <div v-else class="flex flex-col gap-3">
        <div
          v-for="row in rows"
          :key="row.id"
          class="p-4 border rounded-2xl border-n-weak bg-n-solid-1/60"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span class="text-sm font-semibold text-n-slate-12">
              {{ row.productLine }}
            </span>
            <span class="text-sm text-n-slate-11">{{ row.name }}</span>
            <span
              v-if="!row.active"
              class="px-2 py-[2px] text-[12px] rounded-full bg-n-slate-4 text-n-slate-11"
            >
              已停用
            </span>
            <span class="flex-1" />
            <Button
              label="编辑"
              size="sm"
              variant="outline"
              color="slate"
              @click="openEdit(row)"
            />
            <Button
              label="删除"
              size="sm"
              variant="outline"
              color="ruby"
              @click="remove(row)"
            />
          </div>
          <p v-if="row.description" class="mt-1 text-xs text-n-slate-10">
            {{ row.description }}
          </p>
          <div class="flex flex-wrap gap-1.5 mt-2">
            <span
              v-for="f in row.formFields || []"
              :key="f.key"
              class="px-2 py-[2px] text-[12px] rounded-full bg-n-alpha-1 text-n-slate-11"
            >
              {{ f.label }}
              <span class="text-n-slate-10">· {{ typeLabel(f.type) }}</span>
              <span v-if="f.required" class="text-n-ruby-11">*</span>
            </span>
            <span
              v-if="!(row.formFields || []).length"
              class="text-xs text-n-slate-10"
            >
              还没配字段
            </span>
          </div>
        </div>
      </div>
    </div>

    <Dialog
      ref="dialogRef"
      overflow-y-auto
      width="3xl"
      :title="editing ? '编辑模板' : '新建模板'"
      description="字段名用英文（存数据用），显示名是业务员看到的文字。"
      confirm-button-label="保存"
      :confirm-button-color="goColor"
      :is-loading="saving"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="save"
      @close="markPristine"
      @save="save"
    >
      <div class="flex flex-col gap-3">
        <div class="grid grid-cols-2 gap-3">
          <label class="flex flex-col gap-1">
            <span class="text-sm text-n-slate-11">产品线 *</span>
            <input
              v-model="form.productLine"
              type="text"
              class="w-full h-10 px-3 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-sm text-n-slate-11">模板名称 *</span>
            <input
              v-model="form.name"
              type="text"
              class="w-full h-10 px-3 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
            />
          </label>
        </div>

        <label class="flex flex-col gap-1">
          <span class="text-sm text-n-slate-11">说明</span>
          <input
            v-model="form.description"
            type="text"
            class="w-full h-10 px-3 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
          />
        </label>

        <label class="flex items-center gap-2">
          <input
            v-model="form.active"
            type="checkbox"
            class="reset-base size-4"
          />
          <span class="text-sm text-n-slate-11">
            启用（停用后业务员发起申请时看不到这个模板，已有申请不受影响）
          </span>
        </label>

        <div class="flex items-center gap-2 mt-2">
          <span class="text-sm font-medium text-n-slate-12">参数字段</span>
          <span class="flex-1" />
          <Button
            label="加一个字段"
            icon="i-lucide-plus"
            size="sm"
            variant="outline"
            color="slate"
            @click="addField"
          />
        </div>

        <p
          v-if="!form.fields.length"
          class="py-4 text-xs text-center text-n-slate-10"
        >
          还没有字段，点「加一个字段」开始配
        </p>

        <div
          v-for="(f, i) in form.fields"
          :key="i"
          class="p-3 border rounded-xl border-n-weak bg-n-alpha-1"
        >
          <div class="grid grid-cols-12 gap-2">
            <label class="flex flex-col col-span-3 gap-1">
              <span class="text-xs text-n-slate-10">字段名（英文）</span>
              <input
                v-model="f.key"
                type="text"
                placeholder="size"
                class="w-full h-9 px-2 text-sm border rounded-lg reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none"
              />
            </label>
            <label class="flex flex-col col-span-3 gap-1">
              <span class="text-xs text-n-slate-10">显示名</span>
              <input
                v-model="f.label"
                type="text"
                placeholder="尺寸"
                class="w-full h-9 px-2 text-sm border rounded-lg reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none"
              />
            </label>
            <label class="flex flex-col col-span-3 gap-1">
              <span class="text-xs text-n-slate-10">类型</span>
              <SelectCard v-model="f.type" :options="FIELD_TYPES" block />
            </label>
            <label class="flex flex-col items-center col-span-1 gap-1">
              <span class="text-xs text-n-slate-10">必填</span>
              <input
                v-model="f.required"
                type="checkbox"
                class="mt-2 reset-base size-4"
              />
            </label>
            <div class="flex items-end justify-end col-span-2 gap-1 pb-1">
              <button
                type="button"
                class="text-n-slate-9 hover:text-n-slate-12"
                @click="moveField(i, -1)"
              >
                <span class="i-lucide-arrow-up size-4" />
              </button>
              <button
                type="button"
                class="text-n-slate-9 hover:text-n-slate-12"
                @click="moveField(i, 1)"
              >
                <span class="i-lucide-arrow-down size-4" />
              </button>
              <button
                type="button"
                class="text-n-slate-9 hover:text-n-ruby-11"
                @click="removeField(i)"
              >
                <span class="i-lucide-x size-4" />
              </button>
            </div>
          </div>
          <label v-if="f.type === 'select'" class="flex flex-col gap-1 mt-2">
            <span class="text-xs text-n-slate-10">
              下拉选项（用逗号分隔，例：7寸，10.1寸，15.6寸）
            </span>
            <input
              v-model="f.optionsText"
              type="text"
              class="w-full h-9 px-2 text-sm border rounded-lg reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none"
            />
          </label>
        </div>
      </div>
    </Dialog>
  </div>
</template>
