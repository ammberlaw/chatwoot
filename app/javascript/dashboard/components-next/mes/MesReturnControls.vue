<script setup>
import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

// 单据「退回上一环节 / 重新激活」通用控件，铺在各 MES 操作单据的操作列。
// record 需带后端 mes_return_state 字段：returned / returnable / returnReason。
// store 需实现 returnDocument(id, reason) 与 reactivate(id)（见 stores/mes/_returnActions）。
const props = defineProps({
  record: { type: Object, required: true },
  store: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
});

const dialogRef = ref(null);
const reason = ref('');
const busy = computed(() => props.store.getUIFlags.updatingItem);

const openReturn = () => {
  reason.value = '';
  dialogRef.value?.open();
};

const submitReturn = async () => {
  if (!reason.value.trim()) return;
  const ok = await props.store.returnDocument(
    props.record.id,
    reason.value.trim()
  );
  if (ok) {
    useAlert('已退回上一环节，已通知上游负责人');
    dialogRef.value?.close();
  }
};

const reactivate = async () => {
  const ok = await props.store.reactivate(props.record.id);
  if (ok) useAlert('已重新激活，可继续处理');
};
</script>

<template>
  <span class="inline-flex items-center gap-1">
    <span
      v-if="record.returned"
      class="px-2 py-0.5 text-xs rounded-full bg-n-amber-3 text-n-amber-11"
      :title="record.returnReason || ''"
    >
      已退回
    </span>
    <Button
      v-if="record.returned && canManage"
      label="重新激活"
      variant="ghost"
      color="slate"
      size="sm"
      :is-loading="busy"
      @click="reactivate"
    />
    <Button
      v-else-if="canManage && record.returnable"
      label="退回"
      variant="ghost"
      color="amber"
      size="sm"
      @click="openReturn"
    />

    <Dialog
      ref="dialogRef"
      confirm-button-color="amber"
      title="退回上一环节"
      description="退回后会通知上一环节负责人处理，并记录原因；不改动任何下游数据。"
      confirm-label="退回"
      :is-loading="busy"
      :disable-confirm-button="!reason.trim()"
      @confirm="submitReturn"
    >
      <div class="flex flex-col gap-1">
        <label class="text-heading-3 text-n-slate-12">
          退回原因 <span class="text-n-ruby-11">*</span>
        </label>
        <Input
          v-model="reason"
          placeholder="如：供应商没货，需换供应商，请工程确认替代料"
        />
      </div>
    </Dialog>
  </span>
</template>
