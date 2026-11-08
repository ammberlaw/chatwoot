<script setup>
import { computed, reactive, ref } from 'vue';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// 记一次寄样。字段只有占位符当初承诺的那三件事（寄了什么 / 到哪了 / 客户怎么说），
// 没有审批、不扣库存——业务员寄两台样机给客户试，要的就是「别忘了这事」。
const props = defineProps({
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['save']);

const dialogRef = ref(null);
const editingId = ref(null);

const STATUS_OPTIONS = [
  { value: 'PENDING', label: '待寄出' },
  { value: 'SENT', label: '已寄出' },
  { value: 'DELIVERED', label: '已签收' },
  { value: 'FEEDBACK', label: '已反馈' },
  { value: 'CANCELLED', label: '已取消' },
];

// 「没回音」单独列一项：它最常见，也最该被看见——东西到了人不说话，
// 那是最容易不了了之的地方。
const FEEDBACK_OPTIONS = [
  { value: '', label: '还没有结论' },
  { value: 'SATISFIED', label: '满意' },
  { value: 'NEED_CHANGE', label: '要调整' },
  { value: 'REJECTED', label: '不合适' },
  { value: 'NO_REPLY', label: '没回音' },
];

const blankItem = () => ({ name: '', model: '', quantity: '' });

const form = reactive({
  recipient: '',
  carrier: '',
  trackingNo: '',
  status: 'SENT',
  items: [blankItem()],
  feedbackResult: '',
  feedback: '',
  remark: '',
});

const isEditing = computed(() => !!editingId.value);

const resetForm = () => {
  editingId.value = null;
  Object.assign(form, {
    recipient: '',
    carrier: '',
    trackingNo: '',
    status: 'SENT',
    items: [blankItem()],
    feedbackResult: '',
    feedback: '',
    remark: '',
  });
};

const addItem = () => form.items.push(blankItem());
const removeItem = i => {
  form.items.splice(i, 1);
  if (!form.items.length) form.items.push(blankItem());
};

const open = record => {
  resetForm();
  if (record) {
    editingId.value = record.id;
    form.recipient = record.recipient || '';
    form.carrier = record.carrier || '';
    form.trackingNo = record.tracking_no || '';
    form.status = record.status || 'SENT';
    form.items = (record.items || []).length
      ? record.items.map(x => ({
          name: x.name || '',
          model: x.model || '',
          quantity: x.quantity ?? '',
        }))
      : [blankItem()];
    form.feedbackResult = record.feedback_result || '';
    form.feedback = record.feedback || '';
    form.remark = record.remark || '';
  }
  dialogRef.value?.open();
};

const onSuccess = () => {
  resetForm();
  dialogRef.value?.close();
};

const handleConfirm = () => {
  emit('save', {
    id: editingId.value,
    recipient: form.recipient.trim() || null,
    carrier: form.carrier.trim() || null,
    tracking_no: form.trackingNo.trim() || null,
    status: form.status,
    // 空行不提交——人加了一行又没填，不该变成一条没名没数的明细。
    items: form.items
      .filter(x => (x.name || '').trim() || (x.model || '').trim())
      .map(x => ({
        name: x.name.trim(),
        model: x.model.trim(),
        quantity: x.quantity,
      })),
    feedback_result: form.feedbackResult || null,
    feedback: form.feedback.trim() || null,
    remark: form.remark.trim() || null,
  });
};

defineExpose({ open, onSuccess });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    overflow-y-auto
    confirm-button-color="iris"
    :title="isEditing ? '编辑寄样记录' : '记一次寄样'"
    :is-loading="props.isLoading"
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <div class="flex flex-col gap-5">
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Input
          v-model="form.recipient"
          label="寄给谁"
          placeholder="收件人 / 公司"
        />
        <label class="flex flex-col gap-1">
          <span class="text-label text-n-slate-12">状态</span>
          <SelectCard v-model="form.status" :options="STATUS_OPTIONS" block />
        </label>
        <Input
          v-model="form.carrier"
          label="快递公司"
          placeholder="DHL / FedEx / 顺丰"
        />
        <Input
          v-model="form.trackingNo"
          label="快递单号"
          placeholder="客户问「到哪了」时按这个查"
        />
      </div>

      <div class="flex flex-col gap-2">
        <span class="text-label text-n-slate-12">寄了什么</span>
        <div
          v-for="(it, i) in form.items"
          :key="`it-${i}`"
          class="flex items-center gap-2"
        >
          <Input v-model="it.name" placeholder="品名" class="flex-1" />
          <Input v-model="it.model" placeholder="型号" class="flex-1" />
          <Input v-model="it.quantity" placeholder="数量" class="w-24" />
          <button
            type="button"
            class="p-1 reset-base text-n-slate-10 hover:text-n-ruby-11"
            @click="removeItem(i)"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </div>
        <button
          type="button"
          class="self-start text-xs reset-base text-n-iris-11 hover:underline"
          @click="addItem"
        >
          + 再加一样
        </button>
      </div>

      <div class="flex flex-col gap-4">
        <label class="flex flex-col gap-1">
          <span class="text-label text-n-slate-12">客户反馈</span>
          <SelectCard
            v-model="form.feedbackResult"
            :options="FEEDBACK_OPTIONS"
            block
          />
        </label>
        <TextArea
          v-model="form.feedback"
          placeholder="客户试完说了什么——要改哪里、哪儿不满意、什么时候下单"
        />
      </div>

      <TextArea v-model="form.remark" label="备注" placeholder="选填" />
    </div>
  </Dialog>
</template>
