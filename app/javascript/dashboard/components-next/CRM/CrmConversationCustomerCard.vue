<script setup>
import { ref, computed, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
/* global axios */
import CustomerAPI from 'dashboard/api/crm/customers';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

// 会话右侧的客户卡片：业务员在聊天里就看得到这个客户的 CRM 全貌（阶段/星级/归属/
// 在谈商机/累计成交/下次跟进），并能就地写跟进——不用切到客户页再切回来。
const props = defineProps({
  contact: { type: Object, default: () => ({}) },
});

const { accountId } = useAccount();
const router = useRouter();

const STATUS = {
  PROSPECT: { label: '潜在客户', cls: 'bg-n-alpha-2 text-n-slate-11' },
  FOLLOWING: { label: '跟进中', cls: 'bg-n-blue-3 text-n-blue-11' },
  WON: { label: '成交客户', cls: 'bg-n-teal-3 text-n-teal-11' },
  DORMANT: { label: '沉默客户', cls: 'bg-n-iris-3 text-n-iris-11' },
  LOST: { label: '已流失', cls: 'bg-n-ruby-3 text-n-ruby-11' },
};

const card = ref(null);
const loading = ref(false);
const noteDialogRef = ref(null);
const noteBody = ref('');
const savingNote = ref(false);

const customerId = computed(() => props.contact?.crm_customer_id || null);
const status = computed(() => STATUS[card.value?.customer_status] || null);
const money = computed(() => {
  const v = card.value?.deal_total_rmb || 0;
  if (!v) return '¥0';
  return v >= 10000 ? `¥${(v / 10000).toFixed(1)} 万` : `¥${v.toFixed(0)}`;
});
const nextFollowUp = computed(() =>
  card.value?.next_follow_up_at
    ? card.value.next_follow_up_at.slice(0, 10)
    : null
);
// 下次跟进已过期时标红——业务员最该被提醒的就是这个。
const overdue = computed(
  () =>
    nextFollowUp.value &&
    nextFollowUp.value < new Date().toISOString().slice(0, 10)
);

const load = async () => {
  if (!customerId.value) {
    card.value = null;
    return;
  }
  loading.value = true;
  try {
    const { data } = await CustomerAPI.card(customerId.value);
    card.value = data;
  } catch (error) {
    // 客户属于别的业务员时读不到，卡片不显示，不打扰。
    card.value = null;
  } finally {
    loading.value = false;
  }
};

watch(customerId, load, { immediate: true });

const goDetail = () =>
  router.push({
    name: 'crm_customer_detail_index',
    params: { accountId: accountId.value, id: customerId.value },
  });

const goOpportunities = () =>
  router.push({
    name: 'crm_funnel_index',
    params: { accountId: accountId.value },
    query: { customer_id: String(customerId.value) },
  });

const openNote = () => {
  noteBody.value = '';
  noteDialogRef.value?.open();
};

const saveNote = async () => {
  if (!noteBody.value.trim()) {
    useAlert('写点内容再保存');
    return;
  }
  savingNote.value = true;
  try {
    const text = noteBody.value.trim();
    // title 是必填且列表主要显示它；长文再放 body，与客户页的跟进记录同结构。
    await axios.post(
      `/api/v1/accounts/${accountId.value}/crm/follow_up_notes`,
      {
        note: {
          title: text.length > 40 ? `${text.slice(0, 40)}…` : text,
          body: text.length > 40 ? text : null,
          crm_customer_id: customerId.value,
          contact_id: props.contact?.id,
          // 会话多是 WhatsApp 进来的，默认按 WhatsApp 记；不准业务能在客户页改。
          follow_up_method: 'WHATSAPP',
        },
      }
    );
    noteDialogRef.value?.close();
    useAlert('跟进已记录');
    load(); // 最近跟进时间会变
  } catch (error) {
    useAlert(error?.response?.data?.error || '保存失败');
  } finally {
    savingNote.value = false;
  }
};
</script>

<template>
  <div v-if="customerId && card" class="w-full px-4 pb-3">
    <div class="flex flex-col gap-2 p-3 border rounded-xl border-n-weak">
      <div class="flex items-center gap-2 min-w-0">
        <span class="i-lucide-building-2 text-sm text-n-slate-10 shrink-0" />
        <button
          class="flex-1 text-sm font-medium text-left truncate text-n-slate-12 hover:underline"
          @click="goDetail"
        >
          {{ card.name }}
        </button>
        <span
          v-if="status"
          class="px-2 py-0.5 text-[11px] rounded-full shrink-0"
          :class="status.cls"
        >
          {{ status.label }}
        </span>
      </div>

      <div
        class="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-n-slate-11"
      >
        <span v-if="card.star" class="text-n-amber-11">
          {{ '★'.repeat(card.star) }}
        </span>
        <span v-if="card.owner_name">负责人 {{ card.owner_name }}</span>
        <span v-if="card.in_public_pool" class="text-n-iris-11">🌊 公海</span>
      </div>

      <div class="flex items-center gap-4 text-xs">
        <span class="text-n-slate-11">
          累计成交
          <b class="text-n-slate-12">{{ money }}</b>
          <template v-if="card.deal_order_count">
            · {{ card.deal_order_count }} 单
          </template>
        </span>
        <button
          v-if="card.open_opportunity_count"
          class="text-n-iris-11 hover:underline"
          @click="goOpportunities"
        >
          在谈商机 {{ card.open_opportunity_count }}
        </button>
      </div>

      <div class="flex items-center gap-1 text-xs">
        <span class="text-n-slate-11">下次跟进</span>
        <b
          v-if="nextFollowUp"
          :class="overdue ? 'text-n-ruby-11' : 'text-n-slate-12'"
        >
          {{ nextFollowUp }}{{ overdue ? '（已过期）' : '' }}
        </b>
        <span v-else class="text-n-slate-10">未安排</span>
      </div>

      <div class="flex items-center gap-2 pt-1">
        <Button label="写跟进" size="xs" variant="outline" @click="openNote" />
        <Button
          label="客户详情"
          size="xs"
          variant="outline"
          @click="goDetail"
        />
      </div>
    </div>

    <Dialog
      ref="noteDialogRef"
      :dismissible="false"
      title="记一条跟进"
      :description="card.name"
      confirm-button-label="保存"
      confirm-button-color="iris"
      :disable-confirm-button="savingNote"
      @confirm="saveNote"
    >
      <textarea
        v-model="noteBody"
        rows="5"
        placeholder="聊了什么、客户什么反应、下一步打算做什么"
        class="w-full px-3 py-2 text-sm border rounded-lg reset-base border-n-weak bg-n-solid-1 text-n-slate-12"
      />
    </Dialog>
  </div>
</template>
