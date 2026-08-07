<script setup>
import { reactive, ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import PiSellerProfileAPI from 'dashboard/api/crm/piSellerProfiles';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const emit = defineEmits(['saved']);

const { t } = useI18n();

const dialogRef = ref(null);
const saving = ref(false);
const loading = ref(false);
const form = reactive({ contactName: '', mobile: '', email: '' });

const isValid = computed(
  () => !!form.contactName.trim() && !!form.mobile.trim() && !!form.email.trim()
);

const open = async () => {
  loading.value = true;
  dialogRef.value?.open();
  try {
    const { data } = await PiSellerProfileAPI.get();
    form.contactName = data.contact_name || '';
    form.mobile = data.mobile || '';
    form.email = data.email || '';
  } catch {
    // 首次无预录：留空让业务员填
  } finally {
    loading.value = false;
  }
};

const submit = async () => {
  if (!isValid.value || saving.value) return;
  saving.value = true;
  try {
    await PiSellerProfileAPI.update({
      contact_name: form.contactName.trim(),
      mobile: form.mobile.trim(),
      email: form.email.trim(),
    });
    useAlert(t('CRM.PI.SELLER_PROFILE.SAVED'));
    dialogRef.value?.close();
    emit('saved');
  } catch {
    useAlert(t('CRM.PI.SELLER_PROFILE.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="lg"
    confirm-button-color="iris"
    :title="t('CRM.PI.SELLER_PROFILE.TITLE')"
    :is-loading="saving"
    :disable-confirm-button="!isValid"
    @confirm="submit"
  >
    <div class="flex flex-col gap-4">
      <p class="text-xs text-n-slate-10">
        {{ t('CRM.PI.SELLER_PROFILE.SUBTITLE') }}
      </p>
      <div v-if="loading" class="text-sm text-n-slate-11">
        {{ t('CRM.PI.SELLER_PROFILE.LOADING') }}
      </div>
      <template v-else>
        <Input
          v-model="form.contactName"
          :label="t('CRM.PI.SELLER_PROFILE.CONTACT')"
          :placeholder="t('CRM.PI.SELLER_PROFILE.CONTACT_PLACEHOLDER')"
        />
        <Input
          v-model="form.mobile"
          :label="t('CRM.PI.SELLER_PROFILE.MOBILE')"
          :placeholder="t('CRM.PI.SELLER_PROFILE.MOBILE_PLACEHOLDER')"
        />
        <Input
          v-model="form.email"
          :label="t('CRM.PI.SELLER_PROFILE.EMAIL')"
          :placeholder="t('CRM.PI.SELLER_PROFILE.EMAIL_PLACEHOLDER')"
        />
      </template>
    </div>
  </Dialog>
</template>
