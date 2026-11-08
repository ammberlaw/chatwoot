<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import CrmCustomerAPI from 'dashboard/api/crm/customers';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

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

// 公司自己的邮箱一串 sales23@ / sales28@ 看不出是谁，chip 上直接显示归属人名字；
// 地址仍挂在 title 和悬浮卡里，需要核对时能拿到。外部地址照旧显示地址。
const label = computed(() =>
  info.value?.type === 'colleague' && info.value.name
    ? info.value.name
    : props.address
);

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

// ── 添加到已有的顾客：搜已有客户，把本邮箱收编为其联系人（小满只同步了公司一个联系人时用） ──
const attachDialogRef = ref(null);
const searchQ = ref('');
const searchResults = ref([]);
const searching = ref(false);
const attaching = ref(false);
let searchTimer = null;

const openAttachDialog = () => {
  searchQ.value = '';
  searchResults.value = [];
  attachDialogRef.value?.open();
};

const onSearchInput = () => {
  clearTimeout(searchTimer);
  const q = searchQ.value.trim();
  if (q.length < 2) {
    searchResults.value = [];
    return;
  }
  searchTimer = setTimeout(async () => {
    searching.value = true;
    try {
      const { data } = await CrmCustomerAPI.dedupeSearch({ scope: 'all', q });
      searchResults.value = data.payload || [];
    } catch {
      searchResults.value = [];
    } finally {
      searching.value = false;
    }
  }, 300);
};

const attachToCustomer = async row => {
  if (attaching.value) return;
  attaching.value = true;
  try {
    await CrmCustomerAPI.attachContact(row.id, { email: email.value });
    // 收编后重新识别：chip 上色 + 卡片显示该客户。
    const { data } = await CrmCustomerAPI.identify(email.value);
    IDENTITY_CACHE.set(email.value, data);
    info.value = data;
    attachDialogRef.value?.close();
    useAlert('已添加到该顾客');
  } catch {
    useAlert('添加失败，请重试');
  } finally {
    attaching.value = false;
  }
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
    <span class="truncate" :title="address">{{ label }}</span>

    <!-- 悬浮身份卡 -->
    <div
      v-if="hovering && info"
      class="absolute left-0 z-30 flex flex-col gap-2 p-3 border rounded-lg shadow-lg top-5 w-64 bg-n-solid-1 border-n-weak"
    >
      <div class="flex items-center gap-2">
        <span
          class="px-1.5 py-0.5 text-white text-label-small rounded-full"
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
      <div
        v-if="info.type === 'colleague'"
        class="text-xs break-all text-n-slate-10"
      >
        {{ address }}
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
        <div class="flex items-center gap-3">
          <!-- eslint-disable-next-line @intlify/vue-i18n/no-raw-text -->
          <button
            class="text-xs text-n-blue-11 hover:underline"
            @click="createCustomer"
          >
            新建为客户
          </button>
          <!-- eslint-disable-next-line @intlify/vue-i18n/no-raw-text -->
          <button
            class="text-xs text-n-blue-11 hover:underline"
            @click="openAttachDialog"
          >
            添加到已有的顾客
          </button>
        </div>
      </div>
    </div>

    <!-- 添加到已有的顾客：搜已有客户，点选即把本邮箱收编为其联系人 -->
    <Dialog
      ref="attachDialogRef"
      title="添加到已有的顾客"
      width="lg"
      :show-confirm-button="false"
      cancel-button-label="关闭"
    >
      <div class="flex flex-col gap-3" @mouseenter="onEnter">
        <input
          v-model="searchQ"
          type="text"
          placeholder="搜索客户名称 / 编号 / 联系人…"
          class="reset-base w-full h-9 px-3 text-sm border rounded-lg outline-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-iris-8"
          @input="onSearchInput"
        />
        <div class="text-xs text-n-slate-10">
          把「{{
            address
          }}」加为所选客户的联系人（同公司其他来信人也能被识别归属）。
        </div>
        <div
          class="flex flex-col max-h-64 overflow-y-auto divide-y divide-n-weak"
        >
          <div
            v-if="searching"
            class="py-6 text-sm text-center text-n-slate-10"
          >
            搜索中…
          </div>
          <div
            v-else-if="searchQ.trim().length >= 2 && !searchResults.length"
            class="py-6 text-sm text-center text-n-slate-10"
          >
            没有匹配的客户
          </div>
          <button
            v-for="row in searchResults"
            :key="row.id"
            class="flex items-center justify-between gap-3 px-2 py-2.5 text-left hover:bg-n-alpha-1 disabled:opacity-50"
            :disabled="attaching"
            @click="attachToCustomer(row)"
          >
            <div class="min-w-0">
              <div class="text-sm font-medium truncate text-n-slate-12">
                {{ row.name }}
              </div>
              <div class="flex flex-wrap gap-x-2 text-xs text-n-slate-11">
                <span v-if="row.customer_code">{{ row.customer_code }}</span>
                <span>{{ row.owner }}</span>
              </div>
            </div>
            <span class="text-xs shrink-0 text-n-iris-11" aria-hidden="true"
              >添加</span
            >
          </button>
        </div>
      </div>
    </Dialog>
  </span>
</template>
