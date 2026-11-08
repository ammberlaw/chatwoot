<script setup>
import { useI18n } from 'vue-i18n';
import CrmSettingsLayout from 'dashboard/components-next/CRM/CrmSettingsLayout.vue';
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
const { t: translate } = useI18n();
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
  <CrmSettingsLayout
    width="wide"
    :title="translate('CRM.SETTINGS_PAGE.QUOTES')"
    :description="translate('CRM.SETTINGS_PAGE.QUOTES_NOTE')"
  >
    <template #actions
      ><Button
        :label="translate('CRM.SETTINGS_PAGE.NEW_TEMPLATE')"
        icon="i-lucide-plus"
        :color="goColor"
        @click="openNew"
    /></template>
    <p v-if="loading" class="py-8 text-label text-center text-n-slate-10">
      {{ translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_1') }}
    </p>
    <p
      v-else-if="!rows.length"
      class="py-10 text-label text-center text-n-slate-10"
    >
      {{ translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_2') }}
    </p>

    <div v-else class="grid grid-cols-1 items-start gap-4 lg:grid-cols-2">
      <div
        v-for="row in rows"
        :key="row.id"
        class="p-5 border rounded-2xl border-n-weak bg-n-solid-1 sm:p-6"
      >
        <div class="flex flex-wrap items-center gap-2">
          <span class="text-heading-2 text-n-slate-12">
            {{ row.productLine }}
          </span>
          <span class="text-label text-n-slate-11">{{ row.name }}</span>
          <span
            v-if="!row.active"
            class="px-2 py-[2px] text-label-small bg-n-slate-4 text-n-slate-11 rounded-full"
          >
            {{ translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_3') }}
          </span>
          <span class="flex-1" />
          <Button
            :label="translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_4')"
            size="sm"
            variant="outline"
            color="slate"
            @click="openEdit(row)"
          />
          <Button
            :label="translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_5')"
            size="sm"
            variant="outline"
            color="ruby"
            @click="remove(row)"
          />
        </div>
        <p v-if="row.description" class="mt-1 text-label-small text-n-slate-10">
          {{ row.description }}
        </p>
        <div class="flex flex-wrap gap-2 mt-4">
          <span
            v-for="f in row.formFields || []"
            :key="f.key"
            class="px-2 py-[2px] text-label-small bg-n-alpha-1 text-n-slate-11 rounded-full"
          >
            {{ f.label }}
            <span class="text-n-slate-10">· {{ typeLabel(f.type) }}</span>
            <span v-if="f.required" class="text-n-ruby-11">*</span>
          </span>
          <span
            v-if="!(row.formFields || []).length"
            class="text-label-small text-n-slate-10"
          >
            {{ translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_6') }}
          </span>
        </div>
      </div>
    </div>
    <Dialog
      ref="dialogRef"
      overflow-y-auto
      width="4xl"
      :title="editing ? '编辑模板' : '新建模板'"
      :description="translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_7')"
      :confirm-button-label="
        translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_8')
      "
      :confirm-button-color="goColor"
      :is-loading="saving"
      :dirty="isDirty"
      :dirty-save-label="translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_8')"
      @confirm="save"
      @close="markPristine"
      @save="save"
    >
      <div class="flex flex-col gap-5">
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <label class="flex flex-col gap-1">
            <span class="text-label text-n-slate-11">{{
              translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_9')
            }}</span>
            <input
              v-model="form.productLine"
              type="text"
              class="w-full h-10 px-3 text-label border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-label text-n-slate-11">{{
              translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_10')
            }}</span>
            <input
              v-model="form.name"
              type="text"
              class="w-full h-10 px-3 text-label border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
            />
          </label>
        </div>

        <label class="flex flex-col gap-1">
          <span class="text-label text-n-slate-11">{{
            translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_11')
          }}</span>
          <input
            v-model="form.description"
            type="text"
            class="w-full h-10 px-3 text-label border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
          />
        </label>

        <label class="flex items-center gap-2">
          <input
            v-model="form.active"
            type="checkbox"
            class="reset-base size-4"
          />
          <span class="text-label text-n-slate-11">
            {{ translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_12') }}
          </span>
        </label>

        <div class="flex items-center gap-2 mt-2">
          <span class="text-label font-medium text-n-slate-12">{{
            translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_13')
          }}</span>
          <span class="flex-1" />
          <Button
            :label="translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_14')"
            icon="i-lucide-plus"
            size="sm"
            variant="outline"
            color="slate"
            @click="addField"
          />
        </div>

        <p
          v-if="!form.fields.length"
          class="py-4 text-label text-center text-n-slate-10"
        >
          {{ translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_15') }}
        </p>

        <div
          v-for="(f, i) in form.fields"
          :key="i"
          class="p-3 border rounded-xl border-n-weak bg-n-alpha-1"
        >
          <div class="grid grid-cols-2 gap-4 sm:grid-cols-12">
            <label class="flex flex-col min-w-0 gap-2 sm:col-span-3">
              <span class="text-label text-n-slate-10">{{
                translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_16')
              }}</span>
              <input
                v-model="f.key"
                type="text"
                :placeholder="
                  translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_17')
                "
                class="w-full h-9 px-2 text-label border rounded-lg reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none"
              />
            </label>
            <label class="flex flex-col min-w-0 gap-2 sm:col-span-3">
              <span class="text-label text-n-slate-10">{{
                translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_18')
              }}</span>
              <input
                v-model="f.label"
                type="text"
                :placeholder="
                  translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_19')
                "
                class="w-full h-9 px-2 text-label border rounded-lg reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none"
              />
            </label>
            <label class="flex flex-col min-w-0 gap-2 sm:col-span-3">
              <span class="text-label text-n-slate-10">{{
                translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_20')
              }}</span>
              <SelectCard v-model="f.type" :options="FIELD_TYPES" block />
            </label>
            <label class="flex flex-col items-center gap-2 sm:col-span-1">
              <span class="text-label text-n-slate-10">{{
                translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_21')
              }}</span>
              <input
                v-model="f.required"
                type="checkbox"
                class="mt-2 reset-base size-4"
              />
            </label>
            <div class="flex items-end justify-end gap-1 pb-1 sm:col-span-2">
              <button
                type="button"
                class="grid size-9 place-items-center rounded-lg text-n-slate-9 hover:bg-n-alpha-2 hover:text-n-slate-12"
                :aria-label="translate('CRM.SETTINGS_PAGE.MOVE_UP')"
                @click="moveField(i, -1)"
              >
                <span class="i-lucide-arrow-up size-4" />
              </button>
              <button
                type="button"
                class="grid size-9 place-items-center rounded-lg text-n-slate-9 hover:bg-n-alpha-2 hover:text-n-slate-12"
                :aria-label="translate('CRM.SETTINGS_PAGE.MOVE_DOWN')"
                @click="moveField(i, 1)"
              >
                <span class="i-lucide-arrow-down size-4" />
              </button>
              <button
                type="button"
                class="grid size-9 place-items-center rounded-lg text-n-slate-9 hover:bg-n-alpha-2 hover:text-n-ruby-11"
                :aria-label="translate('CRM.SETTINGS_PAGE.REMOVE_FIELD')"
                @click="removeField(i)"
              >
                <span class="i-lucide-x size-4" />
              </button>
            </div>
          </div>
          <label v-if="f.type === 'select'" class="flex flex-col gap-1 mt-2">
            <span class="text-label text-n-slate-10">
              {{ translate('CRM.SETTINGS_COPY.QUOTEREQUESTTEMPLATES_22') }}
            </span>
            <input
              v-model="f.optionsText"
              type="text"
              class="w-full h-9 px-2 text-label border rounded-lg reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none"
            />
          </label>
        </div>
      </div>
    </Dialog>
  </CrmSettingsLayout>
</template>
