<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ErpCashAccountAPI from 'dashboard/api/erp/cashAccounts';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

const props = defineProps({ currency: { type: String, required: true } });
const selectedId = defineModel({ type: [String, Number], default: '' });
const { t } = useI18n();
const accounts = ref([]);
const loading = ref(true);
const selected = computed(() =>
  accounts.value.find(a => String(a.id) === String(selectedId.value))
);
const invalid = computed(
  () =>
    Boolean(selectedId.value) &&
    (loading.value ||
      !selected.value ||
      selected.value.currency !== props.currency)
);
const options = computed(() => [
  { value: '', label: t('CRM.ERP_SETTLEMENT.PENDING_ACCOUNT') },
  ...accounts.value
    .filter(
      a =>
        (a.is_active && a.currency === props.currency) ||
        String(a.id) === String(selectedId.value)
    )
    .map(a => ({
      value: a.id,
      label: `${a.name} · ${a.currency}`,
      note: a.ledger_account_id ? '' : t('CRM.ERP_SETTLEMENT.NO_LEDGER'),
    })),
]);
onMounted(async () => {
  try {
    const { data } = await ErpCashAccountAPI.get();
    accounts.value = data.payload || [];
  } catch {
    useAlert(t('CRM.ERP_SETTLEMENT.ACCOUNTS_ERROR'));
  } finally {
    loading.value = false;
  }
});
defineExpose({ invalid });
</script>

<template>
  <div class="flex flex-col gap-1" data-settlement-cash-account>
    <label class="text-label text-n-slate-12">{{
      t('CRM.ERP_SETTLEMENT.CASH_ACCOUNT')
    }}</label>
    <ComboBox
      v-model="selectedId"
      :options="options"
      :disabled="loading"
      :placeholder="t('CRM.ERP_SETTLEMENT.CASH_ACCOUNT')"
    />
    <span v-if="invalid" class="text-label-small text-n-ruby-11">{{
      t('CRM.ERP_SETTLEMENT.CURRENCY_MISMATCH')
    }}</span>
    <span v-else-if="!selectedId" class="text-label-small text-n-amber-11">{{
      t('CRM.ERP_SETTLEMENT.PENDING_HINT')
    }}</span>
    <span
      v-else-if="selected && !selected.ledger_account_id"
      class="text-label-small text-n-amber-11"
      >{{ t('CRM.ERP_SETTLEMENT.NO_LEDGER') }}</span
    >
  </div>
</template>
