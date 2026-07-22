<script setup>
import { computed } from 'vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { specFieldsFor } from 'dashboard/routes/dashboard/mes/pages/orderSpecFields';

const props = defineProps({
  template: { type: String, default: 'TABLET' },
  readonly: { type: Boolean, default: false },
});
// 就地双向绑定的规格对象（父层用 v-model:spec 传入；只读展示可用 :spec）。
const spec = defineModel('spec', { type: Object, required: true });

const fields = computed(() => specFieldsFor(props.template));

const toggleCheck = (key, opt) => {
  const arr = spec.value[key] || (spec.value[key] = []);
  const i = arr.indexOf(opt);
  if (i >= 0) arr.splice(i, 1);
  else arr.push(opt);
};
const dualo = key => {
  if (!spec.value[key]) spec.value[key] = { mode: '默认', spec: '' };
  return spec.value[key];
};

// 切换默认/其他：切回默认且为空时回填标准值；从默认切到其他时清掉标准值好填自定义。
const setDualoMode = (f, mode) => {
  const d = dualo(f.key);
  if (mode === '默认' && !d.spec) d.spec = f.defaultHint || '';
  else if (mode === '其他' && d.spec === f.defaultHint) d.spec = '';
  d.mode = mode;
};

// 只读展示时把值转成一句话。
const displayValue = f => {
  const v = spec.value[f.key];
  if (f.type === 'checks') return (v || []).join('、') || '—';
  if (f.type === 'dualo') {
    const text = v?.spec || (v?.mode === '其他' ? '' : f.defaultHint);
    if (v?.mode === '其他') return `其他：${text || '—'}`;
    return text || '默认';
  }
  return v || '—';
};
const hasValue = f => {
  const v = spec.value[f.key];
  if (f.type === 'checks') return (v || []).length;
  if (f.type === 'dualo') return v?.spec || f.defaultHint;
  return v;
};
</script>

<template>
  <!-- 只读展示（详情面板） -->
  <dl v-if="readonly" class="grid grid-cols-2 text-sm gap-x-4 gap-y-1.5">
    <template v-for="(f, i) in fields" :key="i">
      <div
        v-if="f.section"
        class="col-span-2 mt-2 text-xs font-medium text-n-slate-11"
      >
        {{ f.section }}
      </div>
      <template v-else-if="hasValue(f) || f.type === 'textarea'">
        <dt class="text-n-slate-11">{{ f.label }}</dt>
        <dd class="text-n-slate-12 whitespace-pre-line">
          {{ displayValue(f) }}
        </dd>
      </template>
    </template>
  </dl>

  <!-- 编辑表单 -->
  <div v-else class="flex flex-col gap-3">
    <template v-for="(f, i) in fields" :key="i">
      <div
        v-if="f.section"
        class="pt-1 text-xs font-medium text-n-slate-11 border-t border-n-weak"
      >
        {{ f.section }}
      </div>

      <div v-else class="flex flex-col gap-1">
        <label class="text-xs text-n-slate-11">{{ f.label }}</label>

        <!-- 多选 -->
        <div v-if="f.type === 'checks'" class="flex flex-wrap gap-3">
          <label
            v-for="opt in f.options"
            :key="opt"
            class="flex items-center gap-1.5 text-sm cursor-pointer text-n-slate-12"
          >
            <input
              type="checkbox"
              class="accent-n-brand"
              :checked="(spec[f.key] || []).includes(opt)"
              @change="toggleCheck(f.key, opt)"
            />
            {{ opt }}
          </label>
        </div>

        <!-- 默认/其他：内容始终可编辑，默认模式回填标准值 -->
        <div v-else-if="f.type === 'dualo'" class="flex items-center gap-2">
          <select
            :value="dualo(f.key).mode"
            class="h-9 px-2 text-sm border rounded-lg outline-none shrink-0 border-n-weak bg-n-alpha-black1 text-n-slate-12"
            @change="e => setDualoMode(f, e.target.value)"
          >
            <option value="默认">默认</option>
            <option value="其他">其他</option>
          </select>
          <Input
            :model-value="dualo(f.key).spec"
            :placeholder="f.defaultHint || '规格/要求'"
            class="flex-1"
            @update:model-value="v => (dualo(f.key).spec = v)"
          />
        </div>

        <!-- 多行 -->
        <textarea
          v-else-if="f.type === 'textarea'"
          v-model="spec[f.key]"
          rows="2"
          class="px-3 py-2 text-sm border rounded-lg outline-none resize-y border-n-weak bg-n-alpha-black1 text-n-slate-12"
        />

        <!-- 单行 -->
        <Input
          v-else
          v-model="spec[f.key]"
          :placeholder="f.placeholder || ''"
        />
      </div>
    </template>
  </div>
</template>
