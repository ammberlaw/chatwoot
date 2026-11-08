<script setup>
import { computed } from 'vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

// 「发起人属于」多选：部门与具体成员混着选（选了部门即含其下级部门，后端 subtree_ids 判定）。
// 值是 ["dept:3","user:17"] 这样的 token 数组，与后端条件引擎约定一致。
const props = defineProps({
  departments: { type: Array, default: () => [] },
  agents: { type: Array, default: () => [] },
});

const picked = defineModel({ type: Array, default: () => [] });

const ADD_HINT = '添加部门或成员…';

const deptName = id =>
  props.departments.find(d => String(d.id) === String(id))?.name || `#${id}`;
const userName = id =>
  props.agents.find(a => String(a.id) === String(id))?.name || `#${id}`;

const tokenLabel = token => {
  const [kind, id] = String(token).split(':');
  return kind === 'dept' ? deptName(id) : userName(id);
};
const isDept = token => String(token).startsWith('dept:');

const options = computed(() => {
  const chosen = picked.value.map(String);
  return [
    { value: '', label: ADD_HINT },
    ...props.departments
      .map(d => ({ value: `dept:${d.id}`, label: d.name, note: '部门' }))
      .filter(o => !chosen.includes(o.value)),
    ...props.agents
      .map(a => ({ value: `user:${a.id}`, label: a.name, note: '成员' }))
      .filter(o => !chosen.includes(o.value)),
  ];
});

const add = token => {
  if (token && !picked.value.includes(token)) picked.value.push(token);
};
const remove = token => {
  const i = picked.value.indexOf(token);
  if (i >= 0) picked.value.splice(i, 1);
};
</script>

<template>
  <div class="flex flex-col gap-1">
    <div v-if="picked.length" class="flex flex-wrap gap-1">
      <span
        v-for="token in picked"
        :key="token"
        class="inline-flex items-center gap-1 px-2 py-0.5 text-label-small rounded-full"
        :class="
          isDept(token)
            ? 'bg-n-iris-3 text-n-iris-11'
            : 'bg-n-slate-3 text-n-slate-11'
        "
      >
        {{ tokenLabel(token) }}
        <button class="hover:text-n-ruby-11" @click="remove(token)">
          <Icon icon="i-lucide-x" class="size-3" />
        </button>
      </span>
    </div>
    <SelectCard
      model-value=""
      :options="options"
      :placeholder="ADD_HINT"
      block
      trigger-class="!h-8 !text-xs"
      @update:model-value="add"
    />
  </div>
</template>
