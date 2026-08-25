<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useErpRole } from 'dashboard/composables/useErpRole';
import { useMapGetter } from 'dashboard/composables/store';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import ErpFiscalPeriodAPI from 'dashboard/api/erp/fiscalPeriods';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

// 期末结账：一个月一行，显示凭证数/待过账/借贷是否平，够条件才让结账。
// 结账会生成损益结转凭证并冻结该期间；反结账限管理员且留痕。
const { erpCan } = useErpRole();
const currentUser = useMapGetter('getCurrentUser');
const canClose = computed(() => erpCan('close'));
const isAdmin = computed(() => currentUser.value?.role === 'administrator');

const money = micros => (micros ? fmtMoney(micros) : '—');
const rows = ref([]);
const loading = ref(false);

const load = async () => {
  loading.value = true;
  try {
    const { data } = await ErpFiscalPeriodAPI.get();
    rows.value = data.payload;
  } finally {
    loading.value = false;
  }
};

const closable = row =>
  canClose.value &&
  row.status === 'OPEN' &&
  row.draft_count === 0 &&
  row.balanced;

const doClose = async row => {
  try {
    const { data } = await ErpFiscalPeriodAPI.close(row.period);
    useAlert(
      data.closing_voucher_no
        ? `${row.period} 已结账，结转凭证 ${data.closing_voucher_no}`
        : `${row.period} 已结账（该期间无损益发生，未生成结转凭证）`
    );
    load();
  } catch (error) {
    useAlert(error?.response?.data?.error || '结账失败');
  }
};

const confirmRef = ref(null);
const reopening = ref(null);
const askReopen = row => {
  reopening.value = row;
  confirmRef.value?.open();
};
const doReopen = async () => {
  try {
    await ErpFiscalPeriodAPI.reopen(reopening.value.period);
    useAlert(`${reopening.value.period} 已反结账，结转凭证已撤销`);
    load();
  } catch (error) {
    useAlert(error?.response?.data?.error || '反结账失败');
  }
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between gap-3 px-6 py-4">
      <div class="flex items-center gap-2">
        <div class="i-lucide-calendar-check size-5 text-n-iris-9" />
        <h1 class="text-xl font-semibold text-n-slate-12">期末结账</h1>
        <span class="text-sm text-n-slate-11">
          结账＝结转损益到本年利润 + 冻结该期间凭证
        </span>
      </div>
      <Button label="刷新" color="slate" size="sm" @click="load" />
    </div>

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="loading" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <table v-else class="w-full max-w-5xl text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium">会计期间</th>
            <th class="px-3 py-3 font-medium text-right">凭证数</th>
            <th class="px-3 py-3 font-medium text-right">待过账</th>
            <th class="px-3 py-3 font-medium text-right">借方合计</th>
            <th class="px-3 py-3 font-medium text-right">贷方合计</th>
            <th class="px-3 py-3 font-medium">试算</th>
            <th class="px-3 py-3 font-medium">状态</th>
            <th class="px-3 py-3 font-medium text-right">操作</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in rows"
            :key="row.period"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-3 py-2 font-mono text-n-slate-12">
              {{ row.period }}
            </td>
            <td class="px-3 py-2 text-right text-n-slate-11">
              {{ row.voucher_count }}
            </td>
            <td
              class="px-3 py-2 text-right"
              :class="row.draft_count ? 'text-n-amber-11' : 'text-n-slate-11'"
            >
              {{ row.draft_count }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.debit_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.credit_micros) }}
            </td>
            <td class="px-3 py-2">
              <span
                class="px-2 py-0.5 text-xs rounded whitespace-nowrap"
                :class="
                  row.balanced
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-ruby-3 text-n-ruby-11'
                "
              >
                {{ row.balanced ? '平' : '不平' }}
              </span>
            </td>
            <td class="px-3 py-2">
              <span
                class="px-2 py-0.5 text-xs rounded whitespace-nowrap"
                :class="
                  row.status === 'CLOSED'
                    ? 'bg-n-slate-3 text-n-slate-11'
                    : 'bg-n-iris-3 text-n-iris-11'
                "
              >
                {{ row.status === 'CLOSED' ? '已结账' : '未结账' }}
              </span>
              <span
                v-if="row.closing_voucher_no"
                class="ml-1 text-xs text-n-slate-10"
              >
                {{ row.closing_voucher_no }}
              </span>
            </td>
            <td class="px-3 py-2">
              <div class="flex items-center justify-end gap-1">
                <Button
                  v-if="row.status === 'OPEN'"
                  label="结账"
                  color="iris"
                  variant="ghost"
                  size="xs"
                  :disabled="!closable(row)"
                  @click="doClose(row)"
                />
                <Button
                  v-else-if="isAdmin"
                  label="反结账"
                  color="ruby"
                  variant="ghost"
                  size="xs"
                  @click="askReopen(row)"
                />
              </div>
            </td>
          </tr>
          <tr v-if="!rows.length">
            <td colspan="8" class="px-3 py-10 text-center text-n-slate-11">
              还没有凭证，无需结账。
            </td>
          </tr>
        </tbody>
      </table>

      <p class="mt-4 text-xs text-n-slate-10">
        结账条件：该期间没有待过账凭证、且借贷试算平衡。结账后凭证冻结，需管理员反结账才能改。
      </p>
    </div>

    <Dialog
      ref="confirmRef"
      type="alert"
      width="sm"
      confirm-button-color="ruby"
      title="反结账"
      :description="`确定把 ${reopening?.period || ''} 重新打开？结转凭证会被撤销，该期间凭证恢复可改，操作会留痕。`"
      confirm-label="反结账"
      @confirm="doReopen"
    />
  </div>
</template>
