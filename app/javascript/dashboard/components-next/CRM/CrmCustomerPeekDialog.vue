<script setup>
/* global axios */
// 客户速览：在别的单据里点客户名就能看这家客户是谁，不用离开当前这张单。
//
// 商机详情里只有一个客户名，想确认「这家是谁、谁在跟、以前成交过多少」就得先关掉
// 商机、跳去客户页、再退回来（2026-11-06 用户要求「点击客户名称弹出客户详情」）。
//
// 用的是轻量的 /customers/:id/card 接口（会话右侧客户卡片同一个），不是整页的 /detail——
// 这里要的是「一眼认出这家客户」，不是在这儿编辑。要改要看全貌，底下那颗按钮跳整页。
import { ref, nextTick } from 'vue';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmStarRating from './CrmStarRating.vue';

const router = useRouter();
const { accountId, accountScopedRoute } = useAccount();

const dialog = ref(null);
const card = ref(null);
const customerId = ref(null);
const loading = ref(false);
const failed = ref(false);
let seq = 0;

const STATUS_LABELS = {
  LEAD: '线索',
  FOLLOWING: '跟进中',
  DEALT: '已成交',
  LOST: '已流失',
};

const load = async () => {
  seq += 1;
  const mine = seq;
  loading.value = true;
  failed.value = false;
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/customers/${customerId.value}/card`
    );
    if (mine === seq) card.value = data;
  } catch {
    if (mine === seq) failed.value = true;
  } finally {
    if (mine === seq) loading.value = false;
  }
};

const close = () => dialog.value?.close();

const open = async id => {
  customerId.value = id;
  card.value = null;
  await nextTick();
  // 商机详情本身就是个 <dialog>，再 showModal 一层会叠在它上面（顶层），不用另做遮罩。
  if (!dialog.value.open) dialog.value.showModal();
  load();
};

const openFullPage = () => {
  close();
  router.push(
    accountScopedRoute('crm_customer_detail_index', { id: customerId.value })
  );
};

const fmtDay = value => (value ? new Date(value).toLocaleDateString() : '—');

defineExpose({ open });
</script>

<template>
  <Teleport to="body">
    <dialog
      ref="dialog"
      aria-labelledby="customer-peek-title"
      class="m-auto w-[calc(100%-32px)] max-w-md overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1 p-0 text-n-slate-12 shadow-2xl backdrop:bg-black/30"
      @click="
        event => {
          if (event.target === dialog) close();
        }
      "
      @close="seq += 1"
    >
      <header
        class="flex items-start justify-between gap-3 px-5 py-4 border-b border-n-weak"
      >
        <h2 id="customer-peek-title" class="m-0 min-w-0 text-heading-2">
          {{ card?.name || '客户' }}
        </h2>
        <Button
          aria-label="关闭"
          icon="i-lucide-x"
          variant="ghost"
          color="slate"
          size="sm"
          @click="close"
        />
      </header>

      <p v-if="loading" class="px-5 py-10 text-sm text-center text-n-slate-10">
        加载中…
      </p>
      <p
        v-else-if="failed"
        class="px-5 py-10 text-sm text-center text-n-slate-10"
      >
        这个客户你没有查看权限，或者已经不在了。
      </p>

      <div v-else-if="card" class="px-5 py-4">
        <div class="flex flex-wrap items-center gap-2 mb-4 text-label-small">
          <span v-if="card.customer_code" class="text-n-slate-10">
            {{ card.customer_code }}
          </span>
          <span
            v-if="STATUS_LABELS[card.customer_status]"
            class="px-2 py-1 rounded-md bg-n-alpha-2"
          >
            {{ STATUS_LABELS[card.customer_status] }}
          </span>
          <span
            v-if="card.in_public_pool"
            class="px-2 py-1 rounded-md bg-n-amber-3 text-n-amber-11"
          >
            公海
          </span>
          <CrmStarRating v-if="card.star" :star="card.star" />
        </div>

        <dl
          class="m-0 grid grid-cols-[5.5rem_minmax(0,1fr)] gap-x-4 gap-y-3 text-label"
        >
          <dt class="text-n-slate-11">归属</dt>
          <dd class="m-0 break-words">{{ card.owner_name || '未分配' }}</dd>
          <dt class="text-n-slate-11">联系人</dt>
          <dd class="m-0 break-words">
            {{ card.primary_contact_name || '—' }}
          </dd>
          <dt class="text-n-slate-11">邮箱</dt>
          <dd class="m-0 break-all">{{ card.contact_email || '—' }}</dd>
          <dt class="text-n-slate-11">电话</dt>
          <dd class="m-0 break-words">{{ card.contact_phone || '—' }}</dd>
          <dt class="text-n-slate-11">国家</dt>
          <dd class="m-0 break-words">{{ card.trade_country || '—' }}</dd>
          <dt class="text-n-slate-11">累计成交</dt>
          <dd class="m-0 tabular-nums">
            ¥ {{ (card.deal_total_rmb || 0).toLocaleString() }}
            <span class="text-n-slate-10">
              · {{ card.deal_order_count || 0 }} 单
            </span>
          </dd>
          <dt class="text-n-slate-11">在谈商机</dt>
          <dd class="m-0 tabular-nums">
            {{ card.open_opportunity_count || 0 }}
          </dd>
          <dt class="text-n-slate-11">下次跟进</dt>
          <dd class="m-0">{{ fmtDay(card.next_follow_up_at) }}</dd>
        </dl>
      </div>

      <footer class="flex justify-end px-5 py-4 border-t border-n-weak">
        <Button
          label="打开客户详情"
          icon="i-lucide-external-link"
          variant="outline"
          color="slate"
          size="sm"
          :disabled="!customerId"
          @click="openFullPage"
        />
      </footer>
    </dialog>
  </Teleport>
</template>
