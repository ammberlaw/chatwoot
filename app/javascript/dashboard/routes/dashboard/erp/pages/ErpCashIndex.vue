<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useErpRole } from 'dashboard/composables/useErpRole';
import { useErpLedgerAccountsStore } from 'dashboard/stores/erp/ledgerAccounts';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import ErpCashAccountAPI from 'dashboard/api/erp/cashAccounts';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';

// 资金账户与出纳日记账：账户余额 = 期初 + 流入 - 流出（流水只增不改，任何时点都能对银行对账单）。
// 收付款单落库会自动记一笔流水；这里另外提供内部划转（成对流水 + 自动凭证）。
const { erpCan } = useErpRole();
const canWrite = computed(() => erpCan('cash'));
const accountStore = useErpLedgerAccountsStore();

const KINDS = [
  { value: 'BANK', label: '银行账户' },
  { value: 'CASH', label: '现金' },
  { value: 'PAYPAL', label: 'PayPal' },
  { value: 'WESTERN_UNION', label: '西联' },
  { value: 'OTHER', label: '其他' },
];
const CURRENCIES = [
  { value: 'CNY', label: '人民币 CNY' },
  { value: 'USD', label: '美元 USD' },
  { value: 'EUR', label: '欧元 EUR' },
];
const KIND_ICON = {
  BANK: 'i-lucide-landmark',
  CASH: 'i-lucide-wallet',
  PAYPAL: 'i-lucide-circle-dollar-sign',
  WESTERN_UNION: 'i-lucide-send',
  OTHER: 'i-lucide-piggy-bank',
};

const money = micros => fmtMoney(micros || 0);
const toMicros = value => Math.round(Number(value || 0) * 1_000_000);
const today = () => new Date().toISOString().slice(0, 10);

const accounts = ref([]);
const transactions = ref([]);
const loading = ref(false);
const filterAccountId = ref('');

const totalByCurrency = computed(() => {
  const map = {};
  accounts.value.forEach(a => {
    map[a.currency] = (map[a.currency] || 0) + a.balance_micros;
  });
  return map;
});

const loadAccounts = async () => {
  const { data } = await ErpCashAccountAPI.get();
  accounts.value = data.payload;
};
const loadTransactions = async () => {
  loading.value = true;
  try {
    const { data } = await ErpCashAccountAPI.transactions({
      cash_account_id: filterAccountId.value || undefined,
    });
    transactions.value = data.payload;
  } finally {
    loading.value = false;
  }
};
const reload = async () => {
  await loadAccounts();
  await loadTransactions();
};

/* ---------------- 账户维护 ---------------- */
const accountDialogRef = ref(null);
const editing = ref(null);
const form = reactive({
  name: '',
  kind: 'BANK',
  currency: 'CNY',
  accountNo: '',
  bankName: '',
  ledgerAccountId: '',
  openingBalance: '',
  isActive: true,
});
const ledgerOptions = computed(() =>
  accountStore.getRecords
    .filter(a => !a.isGroup && ['CASH', 'BANK'].includes(a.accountType))
    .map(a => ({ value: a.id, label: `${a.code} ${a.name}` }))
);
const openAccount = (record = null) => {
  editing.value = record;
  Object.assign(form, {
    name: record?.name || '',
    kind: record?.kind || 'BANK',
    currency: record?.currency || 'CNY',
    accountNo: record?.account_no || '',
    bankName: record?.bank_name || '',
    ledgerAccountId: record?.ledger_account_id || '',
    openingBalance: record
      ? (record.opening_balance_micros / 1_000_000).toFixed(2)
      : '',
    isActive: record ? record.is_active : true,
  });
  accountDialogRef.value?.open();
};
const submitAccount = async () => {
  if (!form.name.trim()) return;
  const payload = {
    cash_account: {
      name: form.name.trim(),
      kind: form.kind,
      currency: form.currency,
      account_no: form.accountNo,
      bank_name: form.bankName,
      ledger_account_id: form.ledgerAccountId || null,
      opening_balance_micros: toMicros(form.openingBalance),
      is_active: form.isActive,
    },
  };
  try {
    if (editing.value)
      await ErpCashAccountAPI.update(editing.value.id, payload);
    else await ErpCashAccountAPI.create(payload);
    useAlert('资金账户已保存');
    accountDialogRef.value?.close();
    reload();
  } catch (error) {
    useAlert(error?.response?.data?.error || '保存失败');
  }
};

/* ---------------- 内部划转 ---------------- */
const transferDialogRef = ref(null);
const transferForm = reactive({
  fromId: '',
  toId: '',
  amount: '',
  happenedAt: today(),
  summary: '',
});
const accountOptions = computed(() =>
  accounts.value.map(a => ({
    value: a.id,
    label: `${a.name}（${a.currency} ${money(a.balance_micros)}）`,
  }))
);
const openTransfer = () => {
  Object.assign(transferForm, {
    fromId: '',
    toId: '',
    amount: '',
    happenedAt: today(),
    summary: '',
  });
  transferDialogRef.value?.open();
};
const transferInvalid = computed(
  () =>
    !transferForm.fromId ||
    !transferForm.toId ||
    transferForm.fromId === transferForm.toId ||
    !transferForm.amount
);
const submitTransfer = async () => {
  if (transferInvalid.value) return;
  try {
    await ErpCashAccountAPI.transfer({
      from_id: transferForm.fromId,
      to_id: transferForm.toId,
      amount_micros: toMicros(transferForm.amount),
      happened_at: transferForm.happenedAt,
      summary: transferForm.summary,
    });
    useAlert('划转完成，已生成成对流水与待过账凭证');
    transferDialogRef.value?.close();
    reload();
  } catch (error) {
    useAlert(error?.response?.data?.error || '划转失败');
  }
};

onMounted(async () => {
  if (!accountStore.getRecords.length) accountStore.get({});
  await reload();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between gap-3 px-6 py-4">
      <div class="flex items-center gap-2">
        <div class="i-lucide-wallet size-5 text-n-iris-9" />
        <h1 class="text-xl font-semibold text-n-slate-12">资金账户</h1>
        <span
          v-for="(amount, currency) in totalByCurrency"
          :key="currency"
          class="text-sm text-n-slate-11"
        >
          {{ currency }} 合计
          <span class="font-mono text-n-slate-12">{{ money(amount) }}</span>
        </span>
      </div>
      <div v-if="canWrite" class="flex items-center gap-2">
        <Button
          label="内部划转"
          color="slate"
          variant="faded"
          size="sm"
          :disabled="accounts.length < 2"
          @click="openTransfer"
        />
        <Button
          label="新建账户"
          color="iris"
          size="sm"
          @click="openAccount()"
        />
      </div>
    </div>

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div class="grid grid-cols-2 gap-3 mb-5 md:grid-cols-4">
        <button
          v-for="cashAccount in accounts"
          :key="cashAccount.id"
          class="flex flex-col gap-2 p-4 text-left transition-colors border shadow-sm rounded-xl border-n-weak bg-n-solid-1 hover:border-n-iris-8"
          :class="{ 'opacity-60': !cashAccount.is_active }"
          @click="canWrite && openAccount(cashAccount)"
        >
          <div class="flex items-center justify-between">
            <span class="text-sm text-n-slate-11">{{ cashAccount.name }}</span>
            <div
              :class="KIND_ICON[cashAccount.kind]"
              class="size-4 text-n-iris-9"
            />
          </div>
          <div class="font-mono text-xl font-semibold text-n-slate-12">
            {{ cashAccount.currency }} {{ money(cashAccount.balance_micros) }}
          </div>
          <div class="text-xs text-n-slate-10">
            {{ cashAccount.kind_label }}
            <span v-if="cashAccount.ledger_account_label">
              · {{ cashAccount.ledger_account_label }}
            </span>
            <span v-else class="text-n-amber-11">
              · 未映射科目，自动凭证不会生成
            </span>
          </div>
        </button>
        <div
          v-if="!accounts.length"
          class="col-span-4 px-3 py-10 text-sm text-center text-n-slate-11"
        >
          还没有资金账户。点右上角「新建账户」把银行户 / 现金 / PayPal
          建起来，并映射到会计科目。
        </div>
      </div>

      <div class="flex items-center gap-2 mb-3">
        <span class="text-sm font-medium text-n-slate-12">出纳日记账</span>
        <SelectCard
          v-model="filterAccountId"
          :options="[{ value: '', label: '全部账户' }, ...accountOptions]"
          @update:model-value="loadTransactions"
        />
        <span class="text-xs text-n-slate-10">
          流水只增不改；单据作废会补一条反向冲销
        </span>
      </div>

      <div v-if="loading" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium">日期</th>
            <th class="px-3 py-3 font-medium">账户</th>
            <th class="px-3 py-3 font-medium">摘要</th>
            <th class="px-3 py-3 font-medium">往来单位</th>
            <th class="px-3 py-3 font-medium text-right">收入</th>
            <th class="px-3 py-3 font-medium text-right">支出</th>
            <th class="px-3 py-3 font-medium">经办</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="transaction in transactions"
            :key="transaction.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
              {{ transaction.happened_at }}
            </td>
            <td class="px-3 py-2 text-n-slate-12">
              {{ transaction.cash_account_name }}
            </td>
            <td class="px-3 py-2 text-n-slate-12">{{ transaction.summary }}</td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ transaction.counterparty || '—' }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-teal-11">
              {{
                transaction.direction === 'IN'
                  ? money(transaction.amount_micros)
                  : ''
              }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-ruby-11">
              {{
                transaction.direction === 'OUT'
                  ? money(transaction.amount_micros)
                  : ''
              }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ transaction.created_by_name || '—' }}
            </td>
          </tr>
          <tr v-if="!transactions.length">
            <td colspan="7" class="px-3 py-10 text-center text-n-slate-11">
              还没有资金流水。登记收付款或做一次内部划转就会出现在这里。
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- 账户维护 -->
    <Dialog
      ref="accountDialogRef"
      width="2xl"
      confirm-button-color="iris"
      :title="editing ? `编辑账户 ${editing.name}` : '新建资金账户'"
      :disable-confirm-button="!form.name"
      @confirm="submitAccount"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-3 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              账户名称 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.name" size="sm" custom-input-class="!h-9" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">类型</label>
            <SelectCard v-model="form.kind" :options="KINDS" block />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">币种</label>
            <SelectCard v-model="form.currency" :options="CURRENCIES" block />
          </div>
        </div>

        <div class="grid grid-cols-3 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">开户行</label>
            <Input
              v-model="form.bankName"
              size="sm"
              custom-input-class="!h-9"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">账号</label>
            <Input
              v-model="form.accountNo"
              size="sm"
              custom-input-class="!h-9"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">期初余额</label>
            <Input
              v-model="form.openingBalance"
              size="sm"
              type="number"
              custom-input-class="!h-9"
            />
          </div>
        </div>

        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">映射会计科目</label>
          <ComboBox
            v-model="form.ledgerAccountId"
            :options="ledgerOptions"
            placeholder="选货币资金类科目（银行存款 / 库存现金）"
          />
          <span class="text-xs text-n-slate-10">
            自动凭证按这个科目记账；不映射的话收付款不会生成待过账凭证
          </span>
        </div>

        <label class="flex items-center gap-2 text-heading-3 text-n-slate-12">
          <input v-model="form.isActive" type="checkbox" class="w-4 h-4" />
          启用（停用后不出现在收付款的账户下拉）
        </label>
      </div>
    </Dialog>

    <!-- 内部划转 -->
    <Dialog
      ref="transferDialogRef"
      width="2xl"
      confirm-button-color="iris"
      title="内部划转"
      :disable-confirm-button="transferInvalid"
      @confirm="submitTransfer"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">转出账户</label>
            <ComboBox
              v-model="transferForm.fromId"
              :options="accountOptions"
              placeholder="选转出账户"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">转入账户</label>
            <ComboBox
              v-model="transferForm.toId"
              :options="accountOptions"
              placeholder="选转入账户"
            />
          </div>
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">划转金额</label>
            <Input
              v-model="transferForm.amount"
              size="sm"
              type="number"
              custom-input-class="!h-9"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">划转日期</label>
            <DatePicker
              v-model="transferForm.happenedAt"
              :clearable="false"
              block
            />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">摘要</label>
          <Input
            v-model="transferForm.summary"
            size="sm"
            custom-input-class="!h-9"
            placeholder="如：补备用金"
          />
        </div>
      </div>
    </Dialog>
  </div>
</template>
