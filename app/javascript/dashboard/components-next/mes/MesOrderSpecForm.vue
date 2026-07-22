<script setup>
import { computed, watch } from 'vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { specFieldsFor } from 'dashboard/routes/dashboard/mes/pages/orderSpecFields';

const props = defineProps({
  template: { type: String, default: 'TABLET' },
  readonly: { type: Boolean, default: false },
});
// 就地双向绑定的规格对象（父层用 v-model:spec 传入；只读展示可用 :spec）。
const spec = defineModel('spec', { type: Object, required: true });

const fields = computed(() => specFieldsFor(props.template));

// 兼容历史 dualo 数据：文本字段里残留的 {mode,spec} 对象拍平成字符串（编辑态）。
watch(
  fields,
  fs => {
    if (props.readonly) return;
    fs.forEach(f => {
      if (f.section || f.type === 'checks') return;
      const v = spec.value[f.key];
      if (v && typeof v === 'object') spec.value[f.key] = v.spec || '';
    });
  },
  { immediate: true }
);

const toggleCheck = (key, opt) => {
  const arr = spec.value[key] || (spec.value[key] = []);
  const i = arr.indexOf(opt);
  if (i >= 0) arr.splice(i, 1);
  else arr.push(opt);
};

// 只读展示时把值转成一句话。
const displayValue = f => {
  const v = spec.value[f.key];
  if (f.type === 'checks') return (v || []).join('、') || '—';
  if (v && typeof v === 'object') return v.spec || '—'; // 兼容历史 dualo
  return v || '—';
};
const hasValue = f => {
  const v = spec.value[f.key];
  if (f.type === 'checks') return (v || []).length;
  if (v && typeof v === 'object') return v.spec; // 兼容历史 dualo
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
