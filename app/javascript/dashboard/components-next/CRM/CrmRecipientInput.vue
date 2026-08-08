<script setup>
// 邮件收件人/抄送/密送输入：已选项以 chip 分开显示（图标区分同事/客户），
// 输入时联想「我的客户联系人 + 同事」，点选或回车/逗号成 chip，退格删末位。
import { ref, computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import RecipientSuggestionsAPI from 'dashboard/api/crm/recipientSuggestions';

const props = defineProps({
  modelValue: { type: Array, default: () => [] }, // [{ email, name, type }]
  placeholder: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue']);

const { accountId } = useAccount();

const query = ref('');
const suggestions = ref([]);
const activeIndex = ref(-1);
const open = ref(false);
let timer = null;

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const selectedEmails = computed(
  () => new Set(props.modelValue.map(r => r.email.toLowerCase()))
);

const addRecipient = r => {
  const email = (r.email || '').trim();
  if (!email || selectedEmails.value.has(email.toLowerCase())) return;
  emit('update:modelValue', [
    ...props.modelValue,
    { email, name: r.name || '', type: r.type || 'manual' },
  ]);
};

const removeAt = i => {
  const next = [...props.modelValue];
  next.splice(i, 1);
  emit('update:modelValue', next);
};

const closeDropdown = () => {
  open.value = false;
  suggestions.value = [];
  activeIndex.value = -1;
};

const commitTyped = () => {
  const raw = query.value.trim().replace(/[;,]$/, '').trim();
  if (!raw) return;
  if (EMAIL_RE.test(raw)) {
    addRecipient({ email: raw });
    query.value = '';
    closeDropdown();
  }
};

const fetchSuggestions = () => {
  clearTimeout(timer);
  const q = query.value.trim();
  if (q.length < 1) {
    suggestions.value = [];
    open.value = false;
    return;
  }
  timer = setTimeout(async () => {
    try {
      const { data } = await RecipientSuggestionsAPI.search(accountId.value, q);
      suggestions.value = (data || []).filter(
        s => !selectedEmails.value.has((s.email || '').toLowerCase())
      );
      activeIndex.value = suggestions.value.length ? 0 : -1;
      open.value = suggestions.value.length > 0;
    } catch {
      suggestions.value = [];
      open.value = false;
    }
  }, 250);
};

const pick = s => {
  addRecipient(s);
  query.value = '';
  closeDropdown();
};

const onKeydown = e => {
  if (e.key === 'ArrowDown' && open.value) {
    e.preventDefault();
    activeIndex.value = (activeIndex.value + 1) % suggestions.value.length;
  } else if (e.key === 'ArrowUp' && open.value) {
    e.preventDefault();
    activeIndex.value =
      (activeIndex.value - 1 + suggestions.value.length) %
      suggestions.value.length;
  } else if (e.key === 'Enter') {
    e.preventDefault();
    if (open.value && activeIndex.value >= 0)
      pick(suggestions.value[activeIndex.value]);
    else commitTyped();
  } else if ((e.key === ',' || e.key === ';') && query.value.trim()) {
    e.preventDefault();
    commitTyped();
  } else if (e.key === 'Backspace' && !query.value && props.modelValue.length) {
    removeAt(props.modelValue.length - 1);
  }
};

const onBlur = () => {
  commitTyped();
  // 延迟关闭让点选下拉项先触发
  setTimeout(closeDropdown, 150);
};

const iconFor = type =>
  type === 'member' ? 'i-lucide-users' : 'i-lucide-user-round';
const chipTitle = r => (r.name ? `${r.name} <${r.email}>` : r.email);
</script>

<template>
  <div
    class="relative flex flex-wrap items-center gap-1.5 min-h-[38px] w-full"
  >
    <span
      v-for="(r, i) in modelValue"
      :key="`${r.email}-${i}`"
      class="inline-flex items-center gap-1 pl-1.5 pr-1 py-0.5 rounded-md text-sm bg-n-slate-3 text-n-slate-12 max-w-full"
      :title="chipTitle(r)"
    >
      <span
        :class="iconFor(r.type)"
        class="size-3.5 shrink-0"
        :title="r.type === 'member' ? '同事' : '客户联系人'"
      />
      <span class="truncate">
        <template v-if="r.name">{{ r.name }}</template>
        <span :class="r.name ? 'text-n-slate-10' : ''">
          {{ r.name ? ` ${r.email}` : r.email }}
        </span>
      </span>
      <button
        type="button"
        class="i-lucide-x size-3.5 shrink-0 text-n-slate-10 hover:text-n-slate-12"
        @click="removeAt(i)"
      />
    </span>

    <input
      v-model="query"
      type="text"
      class="flex-1 min-w-[120px] reset-base bg-transparent border-0 outline-none focus:outline-none focus:ring-0 text-sm text-n-slate-12 placeholder:text-n-slate-9 py-0.5"
      :placeholder="modelValue.length ? '' : placeholder"
      @input="fetchSuggestions"
      @keydown="onKeydown"
      @focus="fetchSuggestions"
      @blur="onBlur"
    />

    <ul
      v-if="open"
      class="absolute left-0 top-full z-50 mt-1 w-full max-h-72 overflow-y-auto rounded-lg border border-n-weak bg-n-solid-1 shadow-lg py-1"
    >
      <li
        v-for="(s, i) in suggestions"
        :key="`${s.email}-${i}`"
        class="flex items-center gap-2 px-3 py-1.5 cursor-pointer text-sm"
        :class="i === activeIndex ? 'bg-n-brand/10' : 'hover:bg-n-alpha-1'"
        @mousedown.prevent="pick(s)"
        @mouseenter="activeIndex = i"
      >
        <span
          :class="iconFor(s.type)"
          class="size-4 shrink-0"
          :title="s.type === 'member' ? '同事' : '客户联系人'"
        />
        <span class="font-medium text-n-slate-12 truncate">{{
          s.name || s.email
        }}</span>
        <span v-if="s.name" class="text-n-slate-10 truncate">{{
          s.email
        }}</span>
        <span
          class="ml-auto shrink-0 text-[10px] px-1.5 py-0.5 rounded"
          :class="
            s.type === 'member'
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-slate-3 text-n-slate-11'
          "
        >
          {{ s.type === 'member' ? '同事' : '客户' }}
        </span>
      </li>
    </ul>
  </div>
</template>
