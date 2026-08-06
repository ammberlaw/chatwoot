<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import CrmCustomerAPI from 'dashboard/api/crm/customers';

// 邮件地址身份 chip：挂载时识别（同事/我的客户/同事客户撞单/陌生人）给图标上色，
// 悬浮展开身份卡；陌生人可一键跳建档预填。识别结果按地址全局缓存。
const props = defineProps({
  address: { type: String, required: true },
});

// 模块级缓存：同一地址整个会话只识别一次。
const IDENTITY_CACHE = new Map();

const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');

const info = ref(null);
const hovering = ref(false);
let hoverTimer = null;

const email = computed(() => props.address.trim().toLowerCase());

onMounted(async () => {
  if (!email.value.includes('@')) return;
  if (IDENTITY_CACHE.has(email.value)) {
    info.value = IDENTITY_CACHE.get(email.value);
    return;
  }
  try {
    const { data } = await CrmCustomerAPI.identify(email.value);
    IDENTITY_CACHE.set(email.value, data);
    info.value = data;
  } catch {
    // 识别失败按未知处理，不打扰阅读
  }
});

// 身份视觉：图标颜色 + 徽标文案
// 蓝=我的客户(私海) / 青=公海客户 / 橙=同事客户(撞单) / 橙=同事 / 灰=陌生人
const style = computed(() => {
  switch (info.value?.type) {
    case 'mine':
      return {
        icon: 'text-n-blue-9',
        badge: '我的客户',
        badgeCls: 'bg-n-blue-9',
      };
    case 'public':
      return {
        icon: 'text-n-teal-9',
        badge: '公海客户',
        badgeCls: 'bg-n-teal-9',
      };
    case 'other':
      return {
        icon: 'text-n-amber-10',
        badge: '同事客户 · 撞单',
        badgeCls: 'bg-n-amber-10',
      };
    case 'colleague':
      return {
        icon: 'text-n-amber-10',
        badge: '同事',
        badgeCls: 'bg-n-amber-10',
      };
    case 'stranger':
      return {
        icon: 'text-n-slate-9',
        badge: '陌生人',
        badgeCls: 'bg-n-slate-9',
      };
    default:
      return { icon: 'text-n-slate-9', badge: '', badgeCls: 'bg-n-slate-9' };
  }
});

const onEnter = () => {
  clearTimeout(hoverTimer);
  hoverTimer = setTimeout(() => {
    hovering.value = true;
  }, 150);
};
const onLeave = () => {
  clearTimeout(hoverTimer);
  hovering.value = false;
};

const openCustomer = () => {
  const c = info.value?.customer;
  if (!c) return;
  router.push({
    name: 'crm_customers_index',
    params: { accountId: accountId.value },
    query: { filter: c.in_public_pool ? 'public_pool' : 'private', q: c.name },
  });
};

const createCustomer = () => {
  router.push({
    name: 'crm_customer_intake_index',
    params: { accountId: accountId.value },
    query: { email: email.value },
  });
};
</script>

<template>
  <span
    class="relative inline-flex items-center gap-1"
    @mouseenter="onEnter"
    @mouseleave="onLeave"
  >
    <span
      class="i-lucide-circle-user-round size-3.5 shrink-0"
      :class="style.icon"
    />
    <span class="truncate">{{ address }}</span>

    <!-- 悬浮身份卡 -->
    <div
      v-if="hovering && info"
      class="absolute left-0 z-30 flex flex-col gap-2 p-3 border rounded-lg shadow-lg top-5 w-64 bg-n-solid-1 border-n-weak"
    >
      <div class="flex items-center gap-2">
        <span
          class="px-1.5 py-0.5 text-[11px] text-white rounded"
          :class="style.badgeCls"
        >
          {{ style.badge }}
        </span>
        <span
          v-if="info.type === 'colleague'"
          class="text-sm font-medium truncate text-n-slate-12"
        >
          {{ info.name }}
        </span>
      </div>

      <template v-if="info.customer">
        <div class="text-sm font-medium truncate text-n-slate-12">
          {{ info.customer.name }}
        </div>
        <div class="flex flex-wrap gap-x-3 text-xs text-n-slate-11">
          <span v-if="info.customer.customer_code">
            {{ info.customer.customer_code }}
          </span>
          <span>{{ info.customer.owner }}</span>
          <span v-if="info.customer.status">{{ info.customer.status }}</span>
        </div>
        <!-- eslint-disable-next-line @intlify/vue-i18n/no-raw-text -->
        <button
          class="self-start text-xs text-n-blue-11 hover:underline"
          @click="openCustomer"
        >
          查看客户
        </button>
      </template>

      <div v-else-if="info.type === 'stranger'" class="flex flex-col gap-1.5">
        <div class="text-xs text-n-slate-10">尚未建档，不属于任何业务员</div>
        <!-- eslint-disable-next-line @intlify/vue-i18n/no-raw-text -->
        <button
          class="self-start text-xs text-n-blue-11 hover:underline"
          @click="createCustomer"
        >
          新建为客户
        </button>
      </div>
    </div>
  </span>
</template>
