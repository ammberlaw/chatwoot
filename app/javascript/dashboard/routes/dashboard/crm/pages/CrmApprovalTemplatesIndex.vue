<script setup>
import { ref, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import TemplatesAPI from 'dashboard/api/oa/approvalTemplates';
import AgentAPI from 'dashboard/api/agents';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const { isAdmin } = useAdmin();

const L = {
  header: '审批模板',
  hint: '定义审批类型的表单字段与审批流程，供全员发起审批时选用。',
  new: '新建模板',
  empty: '还没有模板，点右上「新建模板」',
  edit: '编辑模板',
  create: '新建审批模板',
  name: '模板名称',
  desc: '说明',
  icon: '图标',
  fields: '表单字段',
  addField: '添加字段',
  fieldLabel: '字段名',
  fieldType: '类型',
  required: '必填',
  options: '选项（逗号分隔）',
  flow: '审批流程',
  addStep: '添加审批人',
  stepType: '审批人',
  deptLeader: '申请人部门主管',
  specificUser: '指定成员',
  remove: '删除',
  save: '保存',
  deleteConfirm: '删除该模板？已发起的审批单不受影响。',
  saved: '已保存',
  deleted: '已删除',
  error: '操作失败',
  needName: '请填写模板名称',
  readonly: '仅管理员可维护审批模板',
  fieldCount: n => `${n} 个字段`,
  stepCount: n => `${n} 级审批`,
};

const FIELD_TYPES = [
  { value: 'text', label: '单行文本' },
  { value: 'textarea', label: '多行文本' },
  { value: 'number', label: '数字' },
  { value: 'amount', label: '金额' },
  { value: 'date', label: '日期' },
  { value: 'select', label: '下拉选择' },
];
const ICONS = [
  'i-lucide-plane',
  'i-lucide-receipt',
  'i-lucide-file-check',
  'i-lucide-briefcase',
  'i-lucide-shopping-cart',
  'i-lucide-stamp',
  'i-lucide-clock',
  'i-lucide-banknote',
];

const templates = ref([]);
const agents = ref([]);
const dialogRef = ref(null);
const editingId = ref(null);
let seq = 0;
const nextSeq = () => {
  seq += 1;
  return seq;
};
const form = ref({
  name: '',
  description: '',
  icon: ICONS[2],
  active: true,
  fields: [],
  flow: [],
});

const fetchTemplates = async () => {
  const { data } = await TemplatesAPI.get();
  templates.value = data.payload || [];
};

const resetForm = () => {
  form.value = {
    name: '',
    description: '',
    icon: ICONS[2],
    active: true,
    fields: [],
    flow: [],
  };
};

const openCreate = () => {
  editingId.value = null;
  resetForm();
  dialogRef.value?.open();
};

const openEdit = tpl => {
  editingId.value = tpl.id;
  form.value = {
    name: tpl.name || '',
    description: tpl.description || '',
    icon: tpl.icon || ICONS[2],
    active: tpl.active !== false,
    fields: (tpl.form_fields || []).map(f => ({
      seq: nextSeq(),
      key: f.key,
      label: f.label,
      type: f.type || 'text',
      required: !!f.required,
      optionsText: (f.options || []).join(','),
    })),
    flow: (tpl.flow || []).map(s => ({
      seq: nextSeq(),
      type: s.type || 'dept_leader',
      userId: s.user_id ? String(s.user_id) : '',
    })),
  };
  dialogRef.value?.open();
};

const addField = () => {
  seq += 1;
  form.value.fields.push({
    seq,
    key: `field_${seq}`,
    label: '',
    type: 'text',
    required: false,
    optionsText: '',
  });
};
const removeField = i => form.value.fields.splice(i, 1);

const addStep = () => {
  seq += 1;
  form.value.flow.push({ seq, type: 'dept_leader', userId: '' });
};
const removeStep = i => form.value.flow.splice(i, 1);

const save = async () => {
  if (!form.value.name.trim()) {
    useAlert(L.needName);
    return;
  }
  const payload = {
    name: form.value.name.trim(),
    description: form.value.description.trim() || null,
    icon: form.value.icon,
    active: form.value.active,
    form_fields: form.value.fields.map(f => ({
      key: f.key,
      label: f.label.trim() || f.key,
      type: f.type,
      required: f.required,
      options:
        f.type === 'select'
          ? f.optionsText
              .split(',')
              .map(o => o.trim())
              .filter(Boolean)
          : [],
    })),
    flow: form.value.flow.map(s => ({
      type: s.type,
      user_id: s.type === 'user' && s.userId ? Number(s.userId) : null,
    })),
  };
  try {
    if (editingId.value) {
      await TemplatesAPI.modify(editingId.value, payload);
    } else {
      await TemplatesAPI.save(payload);
    }
    dialogRef.value?.close();
    fetchTemplates();
    useAlert(L.saved);
  } catch {
    useAlert(L.error);
  }
};

const removeTemplate = async () => {
  // eslint-disable-next-line no-alert
  if (!editingId.value || !window.confirm(L.deleteConfirm)) return;
  try {
    await TemplatesAPI.remove(editingId.value);
    dialogRef.value?.close();
    fetchTemplates();
    useAlert(L.deleted);
  } catch {
    useAlert(L.error);
  }
};

onMounted(async () => {
  fetchTemplates();
  try {
    const { data } = await AgentAPI.get();
    agents.value = data || [];
  } catch {
    agents.value = [];
  }
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/55 backdrop-blur-2xl rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5">
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <div>
        <h1 class="text-xl font-medium text-n-slate-12">{{ L.header }}</h1>
        <p class="mt-0.5 text-xs text-n-slate-10">{{ L.hint }}</p>
      </div>
      <Button
        v-if="isAdmin"
        :label="L.new"
        icon="i-lucide-plus"
        color="iris"
        @click="openCreate"
      />
    </div>

    <div v-if="!isAdmin" class="px-6 py-2 text-xs bg-n-iris-3 text-n-iris-11">
      {{ L.readonly }}
    </div>

    <div class="flex-1 px-6 py-4">
      <div
        v-if="!templates.length"
        class="p-8 text-sm text-center text-n-slate-10"
      >
        {{ L.empty }}
      </div>
      <div v-else class="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
        <button
          v-for="tpl in templates"
          :key="tpl.id"
          class="flex items-center gap-3 p-4 text-left transition-shadow border rounded-2xl border-n-weak bg-n-solid-1 hover:shadow-sm hover:border-n-iris-7 disabled:cursor-default"
          :disabled="!isAdmin"
          @click="isAdmin && openEdit(tpl)"
        >
          <div
            class="flex items-center justify-center flex-shrink-0 rounded-lg size-10 bg-n-iris-4 text-n-iris-11"
          >
            <Icon :icon="tpl.icon || 'i-lucide-file-check'" class="size-5" />
          </div>
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <span class="font-medium truncate text-n-slate-12">
                {{ tpl.name }}
              </span>
              <span
                v-if="!tpl.active"
                class="px-1.5 rounded text-[10px] bg-n-slate-3 text-n-slate-10"
              >
                {{ '已停用' }}
              </span>
            </div>
            <div class="text-xs truncate text-n-slate-10">
              {{
                `${L.fieldCount((tpl.form_fields || []).length)} · ${L.stepCount((tpl.flow || []).length)}`
              }}
            </div>
          </div>
        </button>
      </div>
    </div>

    <Dialog
      ref="dialogRef"
      width="2xl"
      overflow-y-auto
      :title="editingId ? L.edit : L.create"
      :confirm-button-label="L.save"
      confirm-button-color="iris"
      @confirm="save"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-3">
          <Input v-model="form.name" :label="L.name" autofocus />
          <Input v-model="form.description" :label="L.desc" />
        </div>

        <!-- 图标 -->
        <div>
          <label class="block mb-1 text-heading-3 text-n-slate-12">
            {{ L.icon }}
          </label>
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="ic in ICONS"
              :key="ic"
              class="flex items-center justify-center border rounded-lg size-9"
              :class="
                form.icon === ic
                  ? 'border-n-iris-9 bg-n-iris-3 text-n-iris-11'
                  : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
              "
              @click="form.icon = ic"
            >
              <Icon :icon="ic" class="size-4" />
            </button>
          </div>
        </div>

        <!-- 表单字段 -->
        <div>
          <div class="flex items-center justify-between mb-1.5">
            <label class="text-heading-3 text-n-slate-12">{{ L.fields }}</label>
            <button
              class="inline-flex items-center gap-1 text-xs text-n-iris-11 hover:underline"
              @click="addField"
            >
              <Icon icon="i-lucide-plus" class="size-3.5" />
              {{ L.addField }}
            </button>
          </div>
          <div class="flex flex-col gap-2">
            <div
              v-for="(f, i) in form.fields"
              :key="f.seq"
              class="flex flex-wrap items-center gap-2 p-2 border rounded-lg border-n-weak"
            >
              <input
                v-model="f.label"
                :placeholder="L.fieldLabel"
                class="flex-1 min-w-[100px] h-8 px-2 text-sm border rounded reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
              />
              <select
                v-model="f.type"
                class="h-8 px-2 text-xs border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
              >
                <option
                  v-for="t in FIELD_TYPES"
                  :key="t.value"
                  :value="t.value"
                >
                  {{ t.label }}
                </option>
              </select>
              <input
                v-if="f.type === 'select'"
                v-model="f.optionsText"
                :placeholder="L.options"
                class="flex-1 min-w-[120px] h-8 px-2 text-sm border rounded reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
              />
              <label
                class="inline-flex items-center gap-1 text-xs cursor-pointer text-n-slate-11"
              >
                <input
                  v-model="f.required"
                  type="checkbox"
                  class="accent-n-iris-9"
                />
                {{ L.required }}
              </label>
              <button
                class="text-n-slate-10 hover:text-n-ruby-11"
                @click="removeField(i)"
              >
                <Icon icon="i-lucide-x" class="size-4" />
              </button>
            </div>
          </div>
        </div>

        <!-- 审批流程 -->
        <div>
          <div class="flex items-center justify-between mb-1.5">
            <label class="text-heading-3 text-n-slate-12">{{ L.flow }}</label>
            <button
              class="inline-flex items-center gap-1 text-xs text-n-iris-11 hover:underline"
              @click="addStep"
            >
              <Icon icon="i-lucide-plus" class="size-3.5" />
              {{ L.addStep }}
            </button>
          </div>
          <div class="flex flex-col gap-2">
            <div
              v-for="(s, i) in form.flow"
              :key="s.seq"
              class="flex items-center gap-2 p-2 border rounded-lg border-n-weak"
            >
              <span
                class="flex items-center justify-center rounded-full size-6 bg-n-iris-4 text-n-iris-11 text-[11px]"
              >
                {{ i + 1 }}
              </span>
              <select
                v-model="s.type"
                class="h-8 px-2 text-xs border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
              >
                <option value="dept_leader">{{ L.deptLeader }}</option>
                <option value="user">{{ L.specificUser }}</option>
              </select>
              <select
                v-if="s.type === 'user'"
                v-model="s.userId"
                class="flex-1 h-8 px-2 text-xs border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
              >
                <option value="">{{ '选择成员…' }}</option>
                <option v-for="a in agents" :key="a.id" :value="String(a.id)">
                  {{ a.name }}
                </option>
              </select>
              <span class="flex-1" />
              <button
                class="text-n-slate-10 hover:text-n-ruby-11"
                @click="removeStep(i)"
              >
                <Icon icon="i-lucide-x" class="size-4" />
              </button>
            </div>
          </div>
        </div>

        <button
          v-if="editingId"
          class="inline-flex items-center self-start gap-1 text-xs text-n-ruby-11 hover:underline"
          @click="removeTemplate"
        >
          <Icon icon="i-lucide-trash-2" class="size-3.5" />
          {{ L.remove }}
        </button>
      </div>
    </Dialog>
  </div>
</template>
