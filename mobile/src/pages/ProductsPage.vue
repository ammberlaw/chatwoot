<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import { fetchProducts, fetchPriceLists } from '@/api/crm';
import { money, shortDate } from '@/utils/format';

defineOptions({ name: 'ProductsPage' });

const router = useRouter();

const tab = ref('products');
const products = ref([]);
const total = ref(0);
const page = ref(1);
const keyword = ref('');

const priceLists = ref([]);
const productLines = ref([]);
const line = ref('');

const loading = ref(true);
const loadingMore = ref(false);
const failed = ref(false);
const staleAt = ref(null);

const hasMore = computed(() => products.value.length < total.value);

const loadProducts = async ({ append = false } = {}) => {
  if (append) loadingMore.value = true;
  else {
    loading.value = true;
    failed.value = false;
    page.value = 1;
  }
  try {
    const r = await fetchProducts({ page: page.value, q: keyword.value || undefined });
    const rows = r.data?.payload || [];
    products.value = append ? [...products.value, ...rows] : rows;
    total.value = r.data?.meta?.count ?? rows.length;
    staleAt.value = r.fromCache ? r.at : null;
  } catch {
    if (!append) failed.value = true;
  } finally {
    loading.value = false;
    loadingMore.value = false;
  }
};

const loadPriceLists = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const r = await fetchPriceLists(line.value);
    priceLists.value = r.data?.payload || [];
    // 产品线清单只在不带筛选时才是全集，带筛选时保留已有的
    if (!line.value) productLines.value = r.data?.product_lines || [];
    staleAt.value = r.fromCache ? r.at : null;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const switchTab = t => {
  if (tab.value === t) return;
  tab.value = t;
  if (t === 'products') loadProducts();
  else loadPriceLists();
};

const switchLine = l => {
  if (line.value === l) return;
  line.value = l;
  loadPriceLists();
};

onMounted(loadProducts);
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader back title="产品与核价">
      <template #below>
        <div class="flex items-center gap-2 px-4 pb-3">
          <button
            v-for="t in [
              { key: 'products', label: '产品库' },
              { key: 'price', label: '核价表' },
            ]"
            :key="t.key"
            type="button"
            class="wt-pill"
            :class="
              tab === t.key
                ? 'wt-pill-on'
                : 'wt-pill-off'
            "
            @click="switchTab(t.key)"
          >
            {{ t.label }}
          </button>
        </div>

        <div v-if="tab === 'products'" class="px-4 pb-3">
          <div class="relative">
            <span
              class="absolute -translate-y-1/2 pointer-events-none left-3 top-1/2 size-4 text-[color:var(--pb-ink-3)] i-lucide-search"
            />
            <input
              v-model="keyword"
              type="search"
              enterkeyhint="search"
              placeholder="搜产品名 / 型号"
              class="pl-9 wt-field"
              @search="loadProducts()"
              @keyup.enter="loadProducts()"
            />
          </div>
        </div>

        <div
          v-else-if="productLines.length"
          class="flex items-center gap-2 px-4 pb-3 overflow-x-auto [&::-webkit-scrollbar]:hidden"
        >
          <button
            v-for="l in ['', ...productLines]"
            :key="l || 'all'"
            type="button"
            class="flex-none wt-pill"
            :class="
              line === l
                ? 'wt-pill-on'
                : 'wt-pill-off'
            "
            @click="switchLine(l)"
          >
            {{ l || '全部' }}
          </button>
        </div>
      </template>
    </PageHeader>

    <div class="flex-1 min-h-0 px-4 pt-3 overflow-y-auto">
      <!-- 产品库 -->
      <DataState
        v-if="tab === 'products'"
        :loading="loading"
        :failed="failed"
        :empty="!products.length"
        :stale-at="staleAt"
        empty-text="没有符合条件的产品"
        @retry="loadProducts()"
      >
        <ul class="flex flex-col gap-2">
          <li v-for="p in products" :key="p.id" class="p-3 wt-card">
            <div class="flex items-start gap-3">
              <div class="flex-1 min-w-0">
                <div class="text-sm font-medium truncate text-[color:var(--pb-ink)]">{{ p.name }}</div>
                <div class="mt-0.5 text-xs truncate text-[color:var(--pb-ink-2)]">
                  {{ [p.sku, p.product_line, p.specification].filter(Boolean).join(' · ') || '—' }}
                </div>
              </div>
              <div v-if="p.sale_price_micros" class="flex-none text-sm font-semibold text-[color:var(--pb-ink)]">
                {{ money(p.sale_price_micros, p.pricing_currency) }}
                <span v-if="p.unit" class="text-xs font-normal text-[color:var(--pb-ink-3)]">/{{ p.unit }}</span>
              </div>
            </div>
          </li>
        </ul>
        <button
          v-if="hasMore"
          type="button"
          class="w-full mt-3 wt-btn-ghost"
          :disabled="loadingMore"
          @click="page += 1; loadProducts({ append: true })"
        >
          {{ loadingMore ? '加载中…' : '加载更多' }}
        </button>
        <div class="h-4" />
      </DataState>

      <!-- 核价表版本 -->
      <DataState
        v-else
        :loading="loading"
        :failed="failed"
        :empty="!priceLists.length"
        :stale-at="staleAt"
        empty-text="这条产品线还没有已发布的核价表"
        @retry="loadPriceLists"
      >
        <ul class="flex flex-col gap-2">
          <li v-for="l in priceLists" :key="l.id">
            <button
              type="button"
              class="w-full p-3 text-left wt-card active:bg-[color:var(--pb-fill)]"
              @click="router.push({ name: 'price-list-detail', params: { id: l.id } })"
            >
              <div class="flex items-start gap-3">
                <div class="flex-1 min-w-0">
                  <div class="text-sm font-medium truncate text-[color:var(--pb-ink)]">{{ l.title }}</div>
                  <div class="mt-0.5 text-xs truncate text-[color:var(--pb-ink-2)]">
                    {{ l.product_line }}
                    <template v-if="l.effective_on"> · {{ shortDate(l.effective_on) }} 生效</template>
                    · {{ l.item_count }} 行
                  </div>
                </div>
                <span class="flex-none px-2 py-1 text-xs rounded-lg bg-[color:var(--pb-fill)] text-[color:var(--pb-ink-2)]">
                  {{ l.status_label }}
                </span>
              </div>
            </button>
          </li>
        </ul>
        <div class="h-4" />
      </DataState>
    </div>
  </div>
</template>
