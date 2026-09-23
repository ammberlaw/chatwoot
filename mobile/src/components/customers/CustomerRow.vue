<script setup>
import { computed } from 'vue';
import { countryLabel } from '@/constants/crm';
import { localTimeOf } from '@/utils/timezone';
import { avatarText } from '@/utils/avatar';

// 一行一个客户。手机端第一眼只给四样：公司名 / 邮箱或联系人 / 国家 / 当地时间。
// 其余字段都进详情页——列表挤满字段就变成网页表格了。
const props = defineProps({
  customer: { type: Object, required: true },
});
defineEmits(['open']);

const sub = computed(
  () => props.customer.contact_email || props.customer.primary_contact_name || '—'
);
const local = computed(() => localTimeOf(props.customer.trade_country));
</script>

<template>
  <button
    type="button"
    class="flex items-center w-full gap-3 px-4 rounded-2xl min-h-[86px] py-3 text-left bg-[color:var(--surface)] transition-opacity active:opacity-60"
    @click="$emit('open', customer.id)"
  >
    <span
      class="grid flex-none rounded-full size-10 place-items-center text-[15px] font-semibold bg-[color:var(--surface-soft)] text-[color:var(--text-secondary)]"
    >
      {{ avatarText(customer.name) }}
    </span>

    <div class="flex-1 min-w-0">
      <div class="truncate text-[16px] font-semibold leading-[21px] text-[color:var(--text)]">
        {{ customer.name }}
      </div>
      <div class="mt-1 truncate text-[13px] leading-[18px] text-[color:var(--text-secondary)]">
        {{ sub }}
      </div>
    </div>

    <div class="flex-none text-right">
      <div class="text-[13px] leading-[18px] truncate text-[color:var(--text-secondary)]">
        {{ countryLabel(customer.trade_country) || '—' }}
      </div>
      <div
        v-if="local"
        class="mt-1 text-[12px] leading-4 tabular-nums text-[color:var(--text-tertiary)]"
      >
        {{ local.time }} {{ local.zone }}
      </div>
    </div>

    <span class="flex-none size-4 text-[color:var(--text-tertiary)] i-lucide-chevron-right" />
  </button>
</template>
