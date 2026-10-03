<script setup>
import { ref, computed, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
/* global axios */
import CustomerAPI from 'dashboard/api/crm/customers';
import { countryFromPhone } from 'dashboard/helper/phoneCountry';
import {
  COUNTRY_LABELS,
  ISO2_TO_COUNTRY,
} from 'dashboard/routes/dashboard/crm/constants/countries';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

// 会话右侧的客户卡片：业务员在聊天里就看得到这个客户的 CRM 全貌（阶段/星级/归属/
// 在谈商机/累计成交/下次跟进），并能就地写跟进——不用切到客户页再切回来。
const props = defineProps({
  contact: { type: Object, default: () => ({}) },
});

const { accountId } = useAccount();
const currentUserId = useMapGetter('getCurrentUserID');
const currentChat = useMapGetter('getSelectedChat');

// 来源按会话所在渠道自动填。线上 12705 个客户里 9565 个连分组都是空的，
// 靠业务员手选基本填不上；而「他从哪来的」这件事会话自己就知道。
const CHANNEL_SOURCE = {
  'Channel::WhatsappWeb': 'WHATSAPP',
  'Channel::Email': 'EMAIL',
};
const SOURCE_LABELS = { WHATSAPP: 'WhatsApp 开发', EMAIL: '邮件开发' };
const guessedSource = computed(
  () => CHANNEL_SOURCE[currentChat.value?.meta?.channel] || null
);
const guessedSourceLabel = computed(
  () => SOURCE_LABELS[guessedSource.value] || null
);

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

// 建档成功后 props.contact 还是旧的（父级不知道 crm_customer_id 变了），
// 用本地 id 顶上，卡片立刻就能显示，不用刷页面。
const createdCustomerId = ref(null);
const createDialogRef = ref(null);
const newName = ref('');
const creating = ref(false);

// 国家按号码推断后一起带进档案。客户面板本来就按号码显示国旗和国名，建档时却要
// 业务员再手选一次，多数人就空着——线上 12705 个客户里靠导入才有国家，新建的常年是空。
const guessedCountry = computed(() => {
  const hit = countryFromPhone(props.contact?.phone_number);
  const key = hit?.iso ? ISO2_TO_COUNTRY[hit.iso] : null;
  return key ? { key, label: COUNTRY_LABELS[key] } : null;
});

// 拼成一句话而不是在模板里塞 <template>：那样每个分支前后都会留空白，
// 渲染出来是「WhatsApp 、国家（…） 、来源（…） 会自动带过去」这种夹空格的句子。
const autofillHint = computed(() => {
  const parts = ['联系人', '电话', 'WhatsApp'];
  if (guessedCountry.value) parts.push(`国家（${guessedCountry.value.label}）`);
  if (guessedSourceLabel.value)
    parts.push(`来源（${guessedSourceLabel.value}）`);
  return `${parts.join('、')}会自动带过去，负责人记在你名下。`;
});

const customerId = computed(
  () => createdCustomerId.value || props.contact?.crm_customer_id || null
);
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
// 换了联系人就把上一个的本地 id 丢掉,否则会把别人的档案显示到这个会话上。
watch(
  () => props.contact?.id,
  () => {
    createdCustomerId.value = null;
  }
);

const openCreate = () => {
  // 预填联系人名，但 WhatsApp 进来的多半是「Mr.」这种占位名，让业务员改成真公司名。
  newName.value = props.contact?.name || '';
  createDialogRef.value?.open();
};

const createCustomer = async () => {
  const name = newName.value.trim();
  if (!name) {
    useAlert('填一个客户名称');
    return;
  }
  creating.value = true;
  try {
    const phone = props.contact?.phone_number || '';
    const { data } = await axios.post(
      `/api/v1/accounts/${accountId.value}/crm/customers`,
      {
        customer: {
          name,
          primary_contact_name: props.contact?.name || null,
          contact_email: props.contact?.email || null,
          contact_phone: phone || null,
          whats_app: phone || null,
          // 归给自己——这个按钮的意义就是「这客户我接了」。
          account_owner_id: currentUserId.value,
          // 国家按号码推断、来源按会话渠道推断（推不出来就不填，别瞎猜）。
          trade_country: guessedCountry.value?.key || null,
          source_channel: guessedSource.value,
          // 后端 link_source_contact 认这个字段，把联系人挂到新档案上。
          contact_id: props.contact?.id,
        },
      }
    );
    createdCustomerId.value = data?.id || data?.payload?.id || null;
    createDialogRef.value?.close();
    useAlert('已建档');
  } catch (error) {
    useAlert(error?.response?.data?.error || '建档失败');
  } finally {
    creating.value = false;
  }
};

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
  <!-- 未建档：以前这里什么都不渲染,业务员被派了活也看不到任何入口。 -->
  <div v-if="!customerId && !loading" class="w-full px-4 pb-3">
    <div
      class="flex flex-col gap-2 p-3 border border-dashed rounded-xl border-n-weak"
    >
      <div class="flex items-center gap-2 text-sm text-n-slate-11">
        <span class="i-lucide-user-round-plus text-sm shrink-0" />
        <span>该客户未建档</span>
      </div>
      <p class="text-xs text-n-slate-10">
        建档后才会出现在「我的客户」里,也才能记跟进、报价、下单。
      </p>
      <div class="flex pt-1">
        <Button label="建档" size="xs" variant="outline" @click="openCreate" />
      </div>
    </div>

    <Dialog
      ref="createDialogRef"
      :dismissible="false"
      title="建档"
      :description="contact?.phone_number || contact?.name || ''"
      confirm-button-label="建档"
      confirm-button-color="iris"
      :disable-confirm-button="creating"
      @confirm="createCustomer"
    >
      <label class="block text-heading-3 text-n-slate-12 mb-1">客户名称</label>
      <input
        v-model="newName"
        type="text"
        placeholder="填公司名,别留「Mr.」这种占位名"
        class="w-full px-3 py-2 text-sm border rounded-lg reset-base border-n-weak bg-n-solid-1 text-n-slate-12"
      />
      <p class="mt-2 text-xs text-n-slate-10">
        {{ autofillHint }}
      </p>
    </Dialog>
  </div>

  <div v-else-if="customerId && card" class="w-full px-4 pb-3">
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
        <span v-if="card.in_public_pool" class="text-n-iris-11">公海</span>
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
