// ERP 金额工具：本位币金额格式化 + 人民币大写。
// 金额一律以 micros（1 元 = 1_000_000）存取，显示与打印统一走这里，避免各页面各写一套四舍五入。

const YUAN = 1_000_000;

export const fmtMoney = micros =>
  micros == null
    ? ''
    : (micros / YUAN).toLocaleString('zh-CN', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      });

const DIGITS = ['零', '壹', '贰', '叁', '肆', '伍', '陆', '柒', '捌', '玖'];
const UNITS = ['', '拾', '佰', '仟'];
const GROUPS = ['', '万', '亿', '万亿'];

// 四位一节转大写：1002 → 壹仟零贰；末尾的零不带出去，由上层拼接时处理。
const groupToCapital = group => {
  let text = '';
  let zeroPending = false;
  const digits = String(group).padStart(4, '0').split('').map(Number);
  digits.forEach((digit, index) => {
    const unit = UNITS[3 - index];
    if (digit === 0) {
      zeroPending = text !== '';
    } else {
      if (zeroPending) text += DIGITS[0];
      zeroPending = false;
      text += DIGITS[digit] + unit;
    }
  });
  return text;
};

/**
 * 人民币大写（会计打印用）：壹拾万元整 / 壹仟零贰元伍分 / 负叁佰元整。
 * @param {number} micros 金额（micros，1 元 = 1_000_000）
 */
export const rmbCapital = micros => {
  const cents = Math.round((micros || 0) / 10_000); // 精确到分，避免浮点误差
  if (cents === 0) return '零元整';

  const negative = cents < 0;
  const abs = Math.abs(cents);
  const yuan = Math.floor(abs / 100);
  const jiao = Math.floor((abs % 100) / 10);
  const fen = abs % 10;

  let integerText = '';
  if (yuan === 0) {
    integerText = '';
  } else {
    let rest = yuan;
    const groups = [];
    while (rest > 0) {
      groups.push(rest % 10000);
      rest = Math.floor(rest / 10000);
    }
    groups.forEach((group, index) => {
      if (group === 0) return;
      const chunk = groupToCapital(group) + GROUPS[index];
      // 与下一节之间要不要补「零」，看的是**下一节**够不够四位：
      // 下节 4567（满四位）→ 壹佰贰拾叁万肆仟…；下节 123 或 0 → 壹万零壹佰贰拾叁 / 壹亿零伍元。
      const needsZero = integerText !== '' && groups[index - 1] < 1000;
      integerText = chunk + (needsZero ? '零' : '') + integerText;
    });
    integerText += '元';
  }

  let decimalText = '';
  if (jiao === 0 && fen === 0) {
    decimalText = yuan === 0 ? '' : '整';
  } else {
    if (jiao > 0) decimalText += `${DIGITS[jiao]}角`;
    if (fen > 0) {
      // 元后直接跟分要补「零」：壹元零伍分
      if (jiao === 0 && yuan > 0) decimalText += DIGITS[0];
      decimalText += `${DIGITS[fen]}分`;
    }
  }

  return `${negative ? '负' : ''}${integerText}${decimalText}`;
};
