<script setup>
// 会话界面的「WhatsApp 开聊」：输客户手机号，直接起一通对话。
//
// 手机 WhatsApp 不需要「加好友」，知道号码就能聊。但这个入口原先只长在
// 「邮箱 / WhatsApp 绑定」设置页里（CrmWhatsappWebBinding），业务员要主动联系
// 新客户得先跑去设置页，或者先在手机上发一条——聊天记录就断在系统外面了。
// 这里把同一个能力搬到消息会话界面，用的是同一个后端接口。
//
// 只走业务员自己绑的**个人号**（Baileys）：官方号（Cloud API）主动发起必须用
// 审核过的模板消息，发不了自由文本，不适合「随手开聊」这个场景。
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import WhatsappWebAPI from 'dashboard/api/crm/whatsappWeb';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

const router = useRouter();

const dialogRef = ref(null);
const numbers = ref([]);
const loading = ref(false);
const busy = ref(false);
const fromInboxId = ref('');
const phone = ref('');
const name = ref('');

// 已连上的号才能发起——没连上的点了必失败，不如不给选。
// ⚠️ 连接态的值是 'open'（Baileys 的连接状态原样透出），不是 'connected'；
// 界面上那个「已连接」只是文案翻译（见 CrmWhatsappWebBinding#statusLabel）。
const options = computed(() =>
  numbers.value
    .filter(n => n.status === 'open')
    .map(n => ({
      value: String(n.inbox_id),
      label: n.phone_number
        ? `${n.name || 'WhatsApp'} · ${n.phone_number}`
        : n.name || 'WhatsApp',
    }))
);
const hasNumber = computed(() => options.value.length > 0);
const invalid = computed(
  () => !fromInboxId.value || !phone.value.replace(/\D/g, '')
);

const load = async () => {
  loading.value = true;
  try {
    const { data } = await WhatsappWebAPI.list();
    numbers.value = data || [];
    // 只有一个号就不用选了
    if (options.value.length === 1) fromInboxId.value = options.value[0].value;
  } catch (e) {
    numbers.value = [];
  } finally {
    loading.value = false;
  }
};

const open = async () => {
  phone.value = '';
  name.value = '';
  dialogRef.value?.open();
  await load();
};

const submit = async () => {
  if (invalid.value || busy.value) return;
  busy.value = true;
  try {
    const { data } = await WhatsappWebAPI.startChat(
      Number(fromInboxId.value),
      phone.value.replace(/\D/g, ''),
      name.value.trim()
    );
    dialogRef.value?.close();
    router.push({
      name: 'inbox_conversation',
      params: { conversation_id: data.conversation_id },
    });
  } catch (error) {
    useAlert(error?.response?.data?.error || '发起失败，请稍后重试');
  } finally {
    busy.value = false;
  }
};

onMounted(load);
defineExpose({ open });
</script>

<template>
  <span>
    <slot name="trigger" :open="open" />

    <Dialog
      ref="dialogRef"
      overflow-y-auto
      :dismissible="false"
      width="md"
      confirm-button-color="iris"
      title="WhatsApp 开聊"
      confirm-button-label="开始聊天"
      :is-loading="busy"
      :disable-confirm-button="invalid"
      @confirm="submit"
    >
      <div v-if="loading" class="py-6 text-sm text-center text-n-slate-10">
        正在取可用号码…
      </div>

      <!-- 一个连上的号都没有时，开聊这件事做不了，直接把人指去绑定页 -->
      <div v-else-if="!hasNumber" class="flex flex-col gap-3 py-2">
        <p class="text-sm text-n-slate-11">还没有已连接的 WhatsApp 个人号。</p>
        <Button
          label="去绑定 WhatsApp"
          variant="outline"
          color="slate"
          size="sm"
          class="self-start"
          @click="
            dialogRef?.close();
            router.push({ name: 'crm_mail_accounts_index' });
          "
        />
      </div>

      <div v-else class="flex flex-col gap-4">
        <div v-if="options.length > 1" class="flex flex-col gap-1">
          <label class="text-label text-n-slate-12">用哪个号发起 *</label>
          <SelectCard
            v-model="fromInboxId"
            class="mt-1"
            :options="options"
            placeholder="选择号码"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-label text-n-slate-12">对方手机号 *</label>
          <Input
            v-model="phone"
            class="mt-1"
            placeholder="含国家码，如 8613800138000"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-label text-n-slate-12">备注名</label>
          <Input v-model="name" class="mt-1" />
        </div>
      </div>
    </Dialog>
  </span>
</template>
