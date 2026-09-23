<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';
import FormField from '@/components/FormField.vue';
import {
  fetchCustomerDetail,
  createCustomer,
  updateCustomer,
  checkCustomerDuplicate,
} from '@/api/crm';
import { useCrmOptions } from '@/composables/useCrmOptions';
import { useAuthStore } from '@/stores/auth';
import {
  COUNTRY_LABELS,
  CUSTOMER_STATUS_LABELS,
  CUSTOMER_LEVEL_LABELS,
  PRODUCT_GROUP_LABELS,
  CONTACT_PREFERENCE_LABELS,
  CURRENCY_LABELS,
  TRADE_REGION_LABELS,
  INDUSTRY_LABELS,
  toOptions,
} from '@/constants/crm';

defineOptions({ name: 'CustomerFormPage' });

const route = useRoute();
const router = useRouter();
const { ensureLoaded, groupOptions, sourceOptions } = useCrmOptions();
const auth = useAuthStore();

const id = computed(() => route.params.id);
const isEdit = computed(() => !!id.value);

const COUNTRY_OPTIONS = toOptions(COUNTRY_LABELS);
const REGION_OPTIONS = toOptions(TRADE_REGION_LABELS);
const INDUSTRY_OPTIONS = toOptions(INDUSTRY_LABELS);
const LEVEL_OPTIONS = toOptions(CUSTOMER_LEVEL_LABELS);
const STATUS_OPTIONS = toOptions(CUSTOMER_STATUS_LABELS);
const PRODUCT_GROUP_OPTIONS = toOptions(PRODUCT_GROUP_LABELS);
const CURRENCY_OPTIONS = toOptions(CURRENCY_LABELS);
const CONTACT_PREF_OPTIONS = toOptions(CONTACT_PREFERENCE_LABELS);

const BLANK = {
  name: '',
  customer_code: '',
  trade_country: '',
  trade_region: '',
  trade_city: '',
  industry: '',
  customer_level: '',
  customer_status: 'PROSPECT',
  customer_group: '',
  source_channel: '',
  product_group: '',
  currency_preference: '',
  website: '',
  address: '',
  primary_contact_name: '',
  contact_job_title: '',
  contact_email: '',
  contact_phone: '',
  whats_app: '',
  wechat: '',
  contact_preference: '',
  customer_remark: '',
};

const form = ref({ ...BLANK });
const loading = ref(false);
const saving = ref(false);
const error = ref('');

// 撞单查重：新建时按名称/邮箱/电话查已有客户，命中就提示归属，避免抢单与重复建档
const dupes = ref([]);

const runDuplicateCheck = async () => {
  if (isEdit.value) return;
  const { name, contact_email: email, contact_phone: phone } = form.value;
  if (!name.trim() && !email.trim() && !phone.trim()) {
    dupes.value = [];
    return;
  }
  try {
    const { data } = await checkCustomerDuplicate({ name, email, phone });
    const hits = [data.email_hit, data.phone_hit, ...(data.name_hits || [])].filter(Boolean);
    // 同一客户可能被多个维度命中，按 id 去重
    dupes.value = [...new Map(hits.map(h => [h.id, h])).values()];
  } catch {
    dupes.value = [];
  }
};

let checkTimer = null;
watch(
  () => [form.value.name, form.value.contact_email, form.value.contact_phone],
  () => {
    clearTimeout(checkTimer);
    checkTimer = setTimeout(runDuplicateCheck, 600);
  }
);

const load = async () => {
  if (!isEdit.value) return;
  loading.value = true;
  try {
    const r = await fetchCustomerDetail(id.value);
    const c = r.data?.customer || {};
    // 只取表单字段，避免把统计字段等一起 PATCH 回后端
    Object.keys(BLANK).forEach(k => {
      form.value[k] = c[k] ?? '';
    });
  } catch {
    error.value = '加载失败，请返回重试';
  } finally {
    loading.value = false;
  }
};

const submit = async () => {
  if (!form.value.name.trim()) {
    error.value = '请填写客户名称';
    return;
  }
  saving.value = true;
  error.value = '';
  try {
    if (isEdit.value) {
      await updateCustomer(id.value, form.value);
      router.back();
    } else {
      // 新建时把自己设为负责人，否则客户落成「未分配」，业务员在「我的」里看不到
      const { data } = await createCustomer({
        ...form.value,
        account_owner_id: auth.user?.id,
      });
      const newId = data?.id || data?.customer?.id;
      // 建完直接进详情页，替换当前记录，返回时回到列表而不是空表单
      router.replace(
        newId ? { name: 'customer-detail', params: { id: newId } } : { name: 'customers' }
      );
    }
  } catch (e) {
    error.value =
      e.response?.data?.message ||
      e.response?.data?.error ||
      (e.response ? `保存失败（HTTP ${e.response.status}）` : '网络不可用，保存失败');
  } finally {
    saving.value = false;
  }
};

onMounted(() => {
  ensureLoaded();
  load();
});
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader back :title="isEdit ? '编辑客户' : '新建客户'" />

    <div class="flex-1 min-h-0 px-4 pt-4 overflow-y-auto">
      <p v-if="loading" class="py-10 text-sm text-center text-[color:var(--pb-ink-2)]">加载中…</p>

      <form v-else class="flex flex-col gap-5" @submit.prevent="submit">
        <section class="flex flex-col gap-4">
          <FormField label="客户名称" required>
            <input v-model="form.name" type="text" placeholder="请输入公司名称" class="wt-field" />
          </FormField>

          <!-- 查重结果只提示不拦截：同名不同公司是常事，由业务员判断 -->
          <div v-if="dupes.length" class="p-3 rounded-xl bg-[color:var(--pb-brand-soft)]">
            <p class="text-xs font-medium text-[color:var(--pb-brand-ink)]">
              库里已有 {{ dupes.length }} 家相似客户
            </p>
            <ul class="mt-1.5 flex flex-col gap-1">
              <li v-for="d in dupes" :key="d.id">
                <button
                  type="button"
                  class="text-sm text-left underline wt-link text-[color:var(--pb-brand-ink)] underline-offset-2"
                  @click="router.replace({ name: 'customer-detail', params: { id: d.id } })"
                >
                  {{ d.name }} · {{ d.owner }}
                </button>
              </li>
            </ul>
          </div>

          <FormField label="客户编号">
            <input
              v-model="form.customer_code"
              type="text"
              placeholder="留空由公司编号规则自定"
              class="wt-field"
            />
          </FormField>

          <div class="grid grid-cols-2 gap-3">
            <FormField label="国家">
              <select v-model="form.trade_country" class="wt-field">
                <option value="">请选择</option>
                <option v-for="o in COUNTRY_OPTIONS" :key="o.value" :value="o.value">
                  {{ o.label }}
                </option>
              </select>
            </FormField>
            <FormField label="区域">
              <select v-model="form.trade_region" class="wt-field">
                <option value="">请选择</option>
                <option v-for="o in REGION_OPTIONS" :key="o.value" :value="o.value">
                  {{ o.label }}
                </option>
              </select>
            </FormField>
          </div>

          <FormField label="城市">
            <input v-model="form.trade_city" type="text" class="wt-field"  placeholder="请输入城市"/>
          </FormField>

          <div class="grid grid-cols-2 gap-3">
            <FormField label="客户状态">
              <select v-model="form.customer_status" class="wt-field">
                <option v-for="o in STATUS_OPTIONS" :key="o.value" :value="o.value">
                  {{ o.label }}
                </option>
              </select>
            </FormField>
            <FormField label="客户等级">
              <select v-model="form.customer_level" class="wt-field">
                <option value="">未评级</option>
                <option v-for="o in LEVEL_OPTIONS" :key="o.value" :value="o.value">
                  {{ o.label }}
                </option>
              </select>
            </FormField>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <FormField label="客户分组">
              <select v-model="form.customer_group" class="wt-field">
                <option value="">请选择</option>
                <option v-for="o in groupOptions" :key="o.value" :value="o.value">
                  {{ o.label }}
                </option>
              </select>
            </FormField>
            <FormField label="客户来源">
              <select v-model="form.source_channel" class="wt-field">
                <option value="">请选择</option>
                <option v-for="o in sourceOptions" :key="o.value" :value="o.value">
                  {{ o.label }}
                </option>
              </select>
            </FormField>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <FormField label="产品分组">
              <select v-model="form.product_group" class="wt-field">
                <option value="">请选择</option>
                <option v-for="o in PRODUCT_GROUP_OPTIONS" :key="o.value" :value="o.value">
                  {{ o.label }}
                </option>
              </select>
            </FormField>
            <FormField label="行业">
              <select v-model="form.industry" class="wt-field">
                <option value="">请选择</option>
                <option v-for="o in INDUSTRY_OPTIONS" :key="o.value" :value="o.value">
                  {{ o.label }}
                </option>
              </select>
            </FormField>
          </div>
        </section>

        <section class="flex flex-col gap-4">
          <h2 class="text-xs font-semibold tracking-wide text-[color:var(--pb-ink-3)]">联系方式</h2>

          <div class="grid grid-cols-2 gap-3">
            <FormField label="联系人">
              <input v-model="form.primary_contact_name" type="text" class="wt-field"  placeholder="请输入姓名"/>
            </FormField>
            <FormField label="职务">
              <input v-model="form.contact_job_title" type="text" class="wt-field"  placeholder="请输入职务"/>
            </FormField>
          </div>

          <FormField label="邮箱">
            <input
              v-model="form.contact_email"
              type="email"
              inputmode="email"
              autocapitalize="off"
              autocorrect="off"
              class="wt-field"
             placeholder="请输入邮箱地址"/>
          </FormField>

          <div class="grid grid-cols-2 gap-3">
            <FormField label="电话">
              <input v-model="form.contact_phone" type="tel" inputmode="tel" class="wt-field"  placeholder="请输入电话"/>
            </FormField>
            <FormField label="WhatsApp">
              <input v-model="form.whats_app" type="tel" inputmode="tel" class="wt-field" />
            </FormField>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <FormField label="微信">
              <input v-model="form.wechat" type="text" autocapitalize="off" class="wt-field" />
            </FormField>
            <FormField label="首选联系方式">
              <select v-model="form.contact_preference" class="wt-field">
                <option value="">请选择</option>
                <option v-for="o in CONTACT_PREF_OPTIONS" :key="o.value" :value="o.value">
                  {{ o.label }}
                </option>
              </select>
            </FormField>
          </div>

          <FormField label="网址">
            <input
              v-model="form.website"
              type="url"
              inputmode="url"
              autocapitalize="off"
              autocorrect="off"
              class="wt-field"
             placeholder="请输入网址"/>
          </FormField>

          <FormField label="地址">
            <input v-model="form.address" type="text" class="wt-field"  placeholder="请输入详细地址"/>
          </FormField>

          <FormField label="结算币种">
            <select v-model="form.currency_preference" class="wt-field">
              <option value="">请选择</option>
              <option v-for="o in CURRENCY_OPTIONS" :key="o.value" :value="o.value">
                {{ o.label }}
              </option>
            </select>
          </FormField>

          <FormField label="备注">
            <textarea v-model="form.customer_remark" rows="3" class="wt-field"  placeholder="补充说明"/>
          </FormField>
        </section>

        <p v-if="error" class="text-sm text-[#C4383C]">{{ error }}</p>
      </form>
    </div>

    <div class="flex-none px-4 pt-2 pb-2 border-t border-[color:var(--pb-sep)] bg-n-background pb-safeBottom">
      <button
        type="button"
        class="w-full wt-btn-primary"
        :disabled="saving || loading"
        @click="submit"
      >
        {{ saving ? '保存中…' : '保存' }}
      </button>
    </div>
  </div>
</template>
