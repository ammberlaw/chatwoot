<script setup>
// 页内「产品档案」速查/速改抽屉。
//
// 为什么要有它：做生产任务单时经常要核对或顺手改一下某颗料的档案（名称写得不对、
// 规格少一段），原来必须先存草稿、退出去、进产品档案改完再回来——一来一回表单还得重填。
// 这里只放做料时真正会改的四项（名称/规格/单位/备注），分组、分类、辅助属性那些
// 维护性字段仍回产品档案页改，省得把整张档案表单搬两份、两边各改各的。
/* global axios */
import { ref, reactive, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import ProductsAPI from 'dashboard/api/mes/products';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const emit = defineEmits(['saved']);

const { accountId } = useAccount();

const open = ref(false);
const loading = ref(false);
const saving = ref(false);
const product = ref(null);
const form = reactive({ name: '', specification: '', unit: '', remark: '' });

const invalid = computed(() => !form.name.trim());

// 可以按 id 开，也可以按物料编码开——BOM 明细存的是编码文本、不存产品 id，
// 所以多数情况下只有编码可用（走已有的批量查码接口解析）。
const show = async p => {
  if (!p?.id && !p?.code) return;
  open.value = true;
  loading.value = true;
  product.value = null;
  try {
    let row;
    if (p.id) {
      const { data } = await ProductsAPI.show(p.id);
      row = data?.payload || data || {};
    } else {
      const { data } = await axios.post(
        `/api/v1/accounts/${accountId.value}/mes/products/lookup`,
        { codes: [p.code] }
      );
      row = data?.payload?.[0]?.product;
      if (!row) {
        useAlert(`产品档案里没有这个编码：${p.code}`);
        open.value = false;
        return;
      }
    }
    product.value = row;
    Object.assign(form, {
      name: row.name || '',
      specification: row.specification || '',
      unit: row.unit || '',
      remark: row.remark || '',
    });
  } catch {
    useAlert('读取产品档案失败');
    open.value = false;
  } finally {
    loading.value = false;
  }
};

const close = () => {
  open.value = false;
};

const save = async () => {
  if (invalid.value || !product.value?.id) return;
  saving.value = true;
  try {
    const { data } = await ProductsAPI.update(product.value.id, {
      product: {
        name: form.name.trim(),
        specification: form.specification.trim(),
        unit: form.unit.trim(),
        remark: form.remark.trim(),
      },
    });
    const saved = data?.payload || data || {};
    useAlert('档案已更新');
    // 把新值交回调用页，用料明细那一行即时跟着变，不用重开单子。
    emit('saved', { id: product.value.id, ...saved, ...form });
    open.value = false;
  } catch (e) {
    useAlert(e?.response?.data?.error || '保存失败，请重试');
  } finally {
    saving.value = false;
  }
};

defineExpose({ show });
</script>

<template>
  <Teleport to="body">
    <template v-if="open">
      <div class="fixed inset-0 z-[70] bg-black/20" @click="close" />
      <div
        class="fixed top-0 right-0 z-[71] flex flex-col w-full h-full max-w-md border-l shadow-2xl bg-n-solid-1 border-n-weak"
      >
        <div
          class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
        >
          <div class="min-w-0">
            <div class="text-sm font-semibold text-n-slate-12">产品档案</div>
            <div class="text-xs truncate text-n-slate-10">
              {{ product?.sku || '—' }}
            </div>
          </div>
          <button
            class="flex items-center justify-center rounded size-8 text-n-slate-10 hover:bg-n-alpha-2"
            @click="close"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </div>

        <div v-if="loading" class="py-16 text-sm text-center text-n-slate-10">
          读取中…
        </div>
        <div v-else class="flex flex-col flex-1 gap-4 p-5 overflow-y-auto">
          <div class="flex flex-col gap-1">
            <label class="text-label text-n-slate-12">
              商品名称 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.name" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-label text-n-slate-12">规格型号</label>
            <Input v-model="form.specification" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-label text-n-slate-12">单位</label>
            <Input v-model="form.unit" placeholder="台 / PCS" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-label text-n-slate-12">备注</label>
            <Input v-model="form.remark" placeholder="工艺要求等" />
          </div>
          <p class="text-label-small text-n-slate-10">
            分组、分类、辅助属性等维护性字段请到「产品档案」页改。
          </p>
        </div>

        <div
          class="flex items-center justify-end gap-2 px-5 py-4 border-t border-n-weak"
        >
          <Button label="取消" variant="link" @click="close" />
          <Button
            label="保存档案"
            color="iris"
            :disabled="invalid || saving"
            :is-loading="saving"
            @click="save"
          />
        </div>
      </div>
    </template>
  </Teleport>
</template>
