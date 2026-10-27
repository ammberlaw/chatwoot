<script setup>
defineProps({ kind: { type: String, required: true } });
</script>

<template>
  <div aria-hidden="true" class="wsh-art pointer-events-none my-2 h-36 w-full overflow-hidden motion-reduce:[&_*]:!animate-none">
    <svg viewBox="0 0 280 160" fill="none" class="h-full w-full" focusable="false">
      <!-- Abstract illustrations only: no simulated business records. -->
      <template v-if="kind === 'crm'">
        <g class="origin-center motion-safe:animate-wsh-back">
          <rect x="60" y="26" width="170" height="86" rx="12" fill="#e7e7df" stroke="#deded4" />
          <circle cx="84" cy="52" r="12" fill="#cbcbbc" />
          <path d="M107 48h70M107 57h42M78 85h104" stroke="#c6c6ba" stroke-width="5" stroke-linecap="round" />
        </g>
        <g class="origin-center motion-safe:animate-wsh-middle">
          <rect x="49" y="38" width="170" height="86" rx="12" fill="#fafaf7" stroke="#deded4" />
          <circle cx="73" cy="64" r="12" fill="#dde4d8" />
          <path d="M96 60h70M96 69h42M67 97h104" stroke="#d4d5ca" stroke-width="5" stroke-linecap="round" />
        </g>
        <g class="origin-center motion-safe:animate-wsh-front">
          <rect x="44" y="53" width="180" height="87" rx="12" fill="#dcdcd2" opacity=".35" />
          <rect x="44" y="49" width="180" height="87" rx="12" fill="white" stroke="#e4e4da" />
          <circle cx="71" cy="77" r="15" fill="#f2e8b7" />
          <circle cx="71" cy="73" r="4" fill="#9a8d50" />
          <path d="M64 84c1-7 13-7 14 0" fill="#9a8d50" />
          <path d="M99 73h70M99 84h45" stroke="#b6b8a8" stroke-width="5" stroke-linecap="round" />
          <rect x="61" y="106" width="52" height="13" rx="6" fill="#f1f1eb" />
          <circle cx="202" cy="112" r="4" fill="#ffcf32" />
        </g>
      </template>
      <template v-else-if="kind === 'mes'">
        <path d="M34 109h210" stroke="#deded3" stroke-width="2" stroke-dasharray="3 6" />
        <g fill="#e6e6dd"><circle cx="52" cy="109" r="7" /><circle cx="140" cy="109" r="7" /><circle cx="228" cy="109" r="7" /></g>
        <g class="motion-safe:animate-wsh-order">
          <rect x="26" y="36" width="70" height="58" rx="10" fill="white" stroke="#deded4" />
          <path d="m48 56 13-7 13 7v17l-13 7-13-7V56Zm0 0 13 7 13-7m-13 7v17" stroke="#acae9a" stroke-width="1.6" stroke-linejoin="round" />
          <circle cx="61" cy="109" r="6" fill="#ffcf32" />
        </g>
        <path d="m225 53 6 6 12-14" stroke="#c3c5b4" stroke-width="3" stroke-linecap="round" />
      </template>
      <template v-else-if="kind === 'oa'">
        <rect x="81" y="23" width="122" height="122" rx="13" fill="#e8e8df" transform="rotate(7 142 84)" />
        <rect x="71" y="16" width="122" height="122" rx="13" fill="white" stroke="#deded4" />
        <rect x="110" y="11" width="44" height="12" rx="6" fill="#d9dbc9" />
        <g stroke="#d9dbcf" stroke-width="5" stroke-linecap="round"><path d="M116 51h52M116 81h43M116 111h48" /></g>
        <g fill="#f0f1e9"><rect x="87" y="42" width="18" height="18" rx="5" /><rect x="87" y="72" width="18" height="18" rx="5" /><rect x="87" y="102" width="18" height="18" rx="5" /></g>
        <g stroke="#878e64" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m91 51 3 3 6-7" class="motion-safe:animate-wsh-check-one" /><path d="m91 81 3 3 6-7" class="motion-safe:animate-wsh-check-two" /><path d="m91 111 3 3 6-7" class="motion-safe:animate-wsh-check-three" /></g>
      </template>
      <template v-else-if="kind === 'team'">
        <g class="motion-safe:animate-wsh-message-one"><rect x="36" y="31" width="164" height="43" rx="13" fill="white" stroke="#e0e0d6" /><circle cx="59" cy="52" r="10" fill="#dce2d5" /><path d="M79 48h84M79 57h57" stroke="#d4d6ca" stroke-width="4" stroke-linecap="round" /></g>
        <g class="motion-safe:animate-wsh-message-two"><rect x="82" y="86" width="164" height="43" rx="13" fill="#ecebdc" stroke="#e0dfcf" /><path d="M100 103h85M100 113h58" stroke="#c5c7ad" stroke-width="4" stroke-linecap="round" /><circle cx="222" cy="107" r="10" fill="#f3dc85" /></g>
      </template>
      <template v-else-if="kind === 'erp'">
        <g class="origin-center motion-safe:animate-wsh-ledger"><rect x="63" y="30" width="147" height="99" rx="12" fill="#e4e4d9" transform="rotate(-8 137 80)" /><rect x="64" y="27" width="147" height="99" rx="12" fill="white" stroke="#deded4" /><path d="M82 50h48M82 63h25" stroke="#d4d6ca" stroke-width="5" stroke-linecap="round" /><rect x="85" y="94" width="17" height="16" rx="3" fill="#d9ddcc" /><rect x="111" y="82" width="17" height="28" rx="3" fill="#c7ceaf" /><rect x="137" y="71" width="17" height="39" rx="3" fill="#b6c092" /><rect x="163" y="60" width="17" height="50" rx="3" fill="#efcf65" /></g>
      </template>
      <template v-else-if="kind === 'hr'">
        <path d="M140 58v27H64v19m76-19h76v19m-76-19v19" stroke="#d7d9cc" stroke-width="2" />
        <rect x="114" y="20" width="52" height="43" rx="12" fill="white" stroke="#deded4" /><circle cx="140" cy="42" r="10" fill="#f2dfa0" />
        <g class="motion-safe:animate-wsh-message-one"><rect x="40" y="104" width="48" height="37" rx="10" fill="white" stroke="#deded4" /><circle cx="64" cy="122" r="9" fill="#dce2d3" /></g>
        <rect x="116" y="104" width="48" height="37" rx="10" fill="white" stroke="#deded4" /><circle cx="140" cy="122" r="9" fill="#d9dbe3" />
        <g class="motion-safe:animate-wsh-message-two"><rect x="192" y="104" width="48" height="37" rx="10" fill="white" stroke="#deded4" /><circle cx="216" cy="122" r="9" fill="#e7daca" /></g>
      </template>
      <template v-else-if="kind === 'tiktok'">
        <g class="origin-center motion-safe:animate-wsh-ledger"><rect x="97" y="14" width="86" height="132" rx="17" fill="white" stroke="#dcded2" /><rect x="123" y="21" width="34" height="5" rx="3" fill="#dbddd2" /><rect x="108" y="37" width="64" height="69" rx="8" fill="#e9ecde" /><path d="m134 58 17 12-17 12V58Z" fill="#bdc3a2" /><path d="M111 119h33M111 129h20" stroke="#d3d6c7" stroke-width="4" stroke-linecap="round" /></g>
        <g class="motion-safe:animate-wsh-message-two"><rect x="164" y="89" width="58" height="40" rx="9" fill="#f3dc87" /><path d="M181 103h24l-3 13h-18l-3-13Zm6 0c0-9 12-9 12 0" stroke="#9d893f" stroke-width="1.6" /></g>
      </template>
      <template v-else-if="kind === 'docs'">
        <g class="origin-center motion-safe:animate-wsh-back"><rect x="85" y="20" width="104" height="113" rx="9" fill="#e6e7dc" stroke="#dadcd0" /></g>
        <g class="origin-center motion-safe:animate-wsh-middle"><rect x="76" y="28" width="104" height="113" rx="9" fill="#f8f8f4" stroke="#dadcd0" /></g>
        <g class="origin-center motion-safe:animate-wsh-front"><rect x="68" y="38" width="104" height="108" rx="9" fill="white" stroke="#dadcd0" /><rect x="82" y="54" width="27" height="25" rx="5" fill="#f3e6ae" /><path d="M83 94h61M83 104h61M83 114h40" stroke="#d5d7ca" stroke-width="4" stroke-linecap="round" /></g>
      </template>
    </svg>
  </div>
</template>
