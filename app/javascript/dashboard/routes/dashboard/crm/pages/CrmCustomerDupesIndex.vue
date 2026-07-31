<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import CrmCustomerAPI from 'dashboard/api/crm/customers';

import Button from 'dashboard/components-next/button/Button.vue';

const router = useRouter();

// 维度顺序即页签顺序；label 同时用于组卡片标题前缀
const DIMENSIONS = [
  { key: 'contact_email', label: '邮箱重复', icon: 'i-lucide-mail' },
  { key: 'contact_phone', label: '电话重复', icon: 'i-lucide-phone' },
  { key: 'whats_app', label: 'WhatsApp 重复', icon: 'i-lucide-message-circle' },
  { key: 'name', label: '同名客户', icon: 'i-lucide-building-2' },
];

// 主动查重检索范围（对齐小满：全部/公司名称/编号/邮箱/邮箱后缀/联系人/电话/社交账号）
const SEARCH_SCOPES = [
  { value: 'all', label: '全部' },
  { value: 'name', label: '公司名称/简称' },
  { value: 'code', label: '客户编号' },
  { value: 'email', label: '邮箱地址' },
  { value: 'email_suffix', label: '邮箱后缀' },
  { value: 'contact', label: '联系人名称' },
  { value: 'phone', label: '电话' },
  { value: 'social', label: '社交账号' },
];

const groups = ref({});
const activeDim = ref('contact_email');
const loading = ref(true);

const searchScope = ref('all');
const searchQuery = ref('');
const searchResults = ref(null); // null=未检索；[]=检索无结果
const searching = ref(false);

const runSearch = async () => {
  const q = searchQuery.value.trim();
  if (q.length < 2) {
    useAlert('请输入至少 2 个字符再查重');
    return;
  }
  searching.value = true;
  try {
    const { data } = await CrmCustomerAPI.dedupeSearch({
      scope: searchScope.value,
      q,
    });
    searchResults.value = data.payload || [];
  } catch {
    useAlert('查重检索失败');
  } finally {
    searching.value = false;
  }
};

const clearSearch = () => {
  searchResults.value = null;
  searchQuery.value = '';
};

const load = async () => {
  loading.value = true;
  try {
    const { data } = await CrmCustomerAPI.duplicates();
    groups.value = data.payload || {};
    // 默认停在第一个有重复的维度
    const firstHit = DIMENSIONS.find(d => (data.payload?.[d.key] || []).length);
    if (firstHit) activeDim.value = firstHit.key;
  } catch {
    useAlert('查重数据加载失败');
  } finally {
    loading.value = false;
  }
};

onMounted(load);

const dimCount = key => (groups.value[key] || []).length;
const activeGroups = computed(() => groups.value[activeDim.value] || []);
const totalCount = computed(() =>
  DIMENSIONS.reduce((sum, d) => sum + dimCount(d.key), 0)
);

// 跳到客户列表并按名称搜索定位；公海客户切公海视图，其余走私海视图
const openCustomer = customer => {
  router.push({
    name: 'crm_customers_index',
    query: {
      filter: customer.in_public_pool ? 'public_pool' : 'private',
      q: customer.name,
    },
  });
};
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto border shadow-lg bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border-white/50 shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between gap-3 px-6 pt-6 pb-4 border-b border-n-weak"
    >
      <div>
        <div class="text-lg font-medium text-n-slate-12">客户查重</div>
        <!-- eslint-disable-next-line @intlify/vue-i18n/no-raw-text -->
        <div class="mt-0.5 text-xs text-n-slate-10">
          全库自动归组重复客户，也可按关键词主动检索；点客户行可跳转处理
        </div>
      </div>
      <Button
        label="重新检测"
        icon="i-lucide-refresh-cw"
        color="slate"
        :is-disabled="loading"
        @click="load"
      />
    </div>

    <!-- 主动查重：居中一体式搜索栏（范围下拉 | 关键词输入 | 清空 | 查重，等高贴合） -->
    <div class="flex justify-center w-full px-6 pt-5 pb-1">
      <div
        class="flex items-stretch w-full max-w-4xl overflow-hidden border rounded-lg h-11 bg-n-solid-1 border-n-weak focus-within:border-n-brand"
      >
        <div class="relative shrink-0">
          <select
            v-model="searchScope"
            class="h-full pl-4 text-sm bg-transparent border-r outline-none appearance-none cursor-pointer w-36 pr-9 border-n-weak text-n-slate-12"
          >
            <option v-for="s in SEARCH_SCOPES" :key="s.value" :value="s.value">
              {{ s.label }}
            </option>
          </select>
          <span
            class="absolute -translate-y-1/2 pointer-events-none i-lucide-chevron-down size-4 right-3 top-1/2 text-n-slate-10"
          />
        </div>
        <input
          v-model="searchQuery"
          type="text"
          name="dedupe-keyword"
          autocomplete="off"
          placeholder="搜索公司名称/简称、客户编号、邮箱地址、邮箱后缀、联系人名称、电话、社交账号"
          class="flex-1 h-full min-w-0 px-4 text-sm bg-transparent outline-none text-n-slate-12 placeholder:text-n-slate-9"
          @keyup.enter="runSearch"
        />
        <button
          v-if="searchResults !== null || searchQuery"
          class="flex items-center h-full px-3 outline-none shrink-0 text-n-slate-10 hover:text-n-slate-12 focus-visible:text-n-slate-12"
          title="清空"
          @click="clearSearch"
        >
          <span class="i-lucide-x size-4" />
        </button>
        <button
          class="flex items-center h-full gap-1.5 px-5 text-sm font-medium text-white outline-none shrink-0 bg-n-brand hover:enabled:brightness-110 focus-visible:brightness-110 disabled:opacity-60"
          :disabled="searching"
          @click="runSearch"
        >
          <span
            :class="
              searching ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-search'
            "
            class="size-4"
          />
          查重
        </button>
      </div>
    </div>

    <!-- 检索结果表（对齐小满列：编号/阶段/公司/联系人/邮箱/电话 + 归属） -->
    <template v-if="searchResults !== null">
      <div
        v-if="!searchResults.length"
        class="flex items-center justify-center flex-1 text-n-slate-10"
      >
        没有匹配的客户，可放心建档
      </div>
      <div v-else class="px-6 py-5">
        <!-- table 的 border-collapse 会吃掉圆角，圆角放外层 div 上裁切 -->
        <div class="overflow-hidden border rounded-xl border-n-weak">
          <table class="w-full text-sm">
            <thead>
              <tr
                class="text-left border-b border-n-weak bg-n-alpha-1 text-n-slate-11"
              >
                <th class="px-4 py-2 font-medium">客户编号</th>
                <th class="px-4 py-2 font-medium">客户阶段</th>
                <th class="px-4 py-2 font-medium">公司名称</th>
                <th class="px-4 py-2 font-medium">联系人名</th>
                <th class="px-4 py-2 font-medium">客户邮箱</th>
                <th class="px-4 py-2 font-medium">客户电话</th>
                <th class="px-4 py-2 font-medium">归属</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="customer in searchResults"
                :key="customer.id"
                class="border-b cursor-pointer border-n-weak last:border-0 hover:bg-n-alpha-1"
                @click="openCustomer(customer)"
              >
                <td class="px-4 py-2 text-n-slate-11">
                  {{ customer.customer_code || '—' }}
                </td>
                <td class="px-4 py-2 text-n-slate-11">
                  {{ customer.status || '—' }}
                </td>
                <td class="px-4 py-2 font-medium text-n-slate-12">
                  {{ customer.name }}
                </td>
                <td class="px-4 py-2 text-n-slate-11">
                  {{ customer.contact_name || '—' }}
                </td>
                <td class="px-4 py-2 text-n-slate-11">
                  {{ customer.email || '—' }}
                </td>
                <td class="px-4 py-2 text-n-slate-11">
                  {{ customer.phone || '—' }}
                </td>
                <td class="px-4 py-2 text-n-slate-11">{{ customer.owner }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <div
          v-if="searchResults.length >= 50"
          class="mt-2 text-xs text-n-slate-10"
        >
          最多显示 50 条，请缩小关键词范围
        </div>
      </div>
    </template>

    <div
      v-else-if="loading"
      class="flex items-center justify-center flex-1 text-n-slate-11"
    >
      正在检测重复客户…
    </div>

    <template v-else>
      <!-- 维度页签 -->
      <div class="flex items-center gap-2 px-6 pt-4">
        <button
          v-for="dim in DIMENSIONS"
          :key="dim.key"
          class="flex items-center gap-1.5 px-3 py-1.5 text-sm rounded-lg border transition-colors"
          :class="
            activeDim === dim.key
              ? 'border-n-brand text-n-brand bg-n-brand/5 font-medium'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
          "
          @click="activeDim = dim.key"
        >
          <span :class="dim.icon" class="size-3.5" />
          {{ dim.label }}
          <span
            class="px-1.5 py-0.5 text-xs rounded-full"
            :class="
              dimCount(dim.key)
                ? 'bg-n-ruby-4 text-n-ruby-11'
                : 'bg-n-alpha-2 text-n-slate-10'
            "
          >
            {{ dimCount(dim.key) }}
          </span>
        </button>
      </div>

      <div
        v-if="!totalCount"
        class="flex flex-col items-center justify-center flex-1 gap-2 text-n-slate-10"
      >
        <span class="i-lucide-badge-check size-8" />
        没有发现重复客户
      </div>

      <div
        v-else-if="!activeGroups.length"
        class="flex items-center justify-center flex-1 text-n-slate-10"
      >
        该维度下没有重复客户
      </div>

      <div v-else class="flex flex-col gap-4 px-6 py-5">
        <div
          v-for="group in activeGroups"
          :key="group.value"
          class="border rounded-xl border-n-weak"
        >
          <div
            class="flex items-center gap-2 px-4 py-2.5 text-sm border-b border-n-weak bg-n-alpha-1 rounded-t-xl"
          >
            <span class="font-medium truncate text-n-slate-12">
              {{ group.value }}
            </span>
            <span
              class="shrink-0 px-1.5 py-0.5 text-xs rounded-full bg-n-ruby-4 text-n-ruby-11"
            >
              {{ group.customers.length }} 条
            </span>
          </div>
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left border-b border-n-weak text-n-slate-10">
                <th class="px-4 font-medium py-1.5">公司名称</th>
                <th class="px-4 font-medium py-1.5">客户编号</th>
                <th class="px-4 font-medium py-1.5">归属</th>
                <th class="px-4 font-medium py-1.5">客户阶段</th>
                <th class="px-4 py-1.5" />
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="customer in group.customers"
                :key="customer.id"
                class="border-b cursor-pointer border-n-weak last:border-0 hover:bg-n-alpha-1"
                @click="openCustomer(customer)"
              >
                <td class="px-4 py-2 font-medium text-n-slate-12">
                  {{ customer.name }}
                </td>
                <td class="px-4 py-2 text-n-slate-11">
                  {{ customer.customer_code || '—' }}
                </td>
                <td class="px-4 py-2 text-n-slate-11">{{ customer.owner }}</td>
                <td class="px-4 py-2 text-n-slate-11">
                  {{ customer.status || '—' }}
                </td>
                <td class="px-4 py-2 text-right text-n-slate-9">
                  <span class="i-lucide-chevron-right size-4" />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </template>
  </div>
</template>
