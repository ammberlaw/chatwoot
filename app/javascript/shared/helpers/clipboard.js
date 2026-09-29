/**
 * Copies text without the async Clipboard API, for pages served over plain HTTP.
 *
 * @param {string} text text to be written to the clipboard
 * @throws {Error} the browser refused the copy command
 */
const copyViaSelection = text => {
  const field = document.createElement('textarea');
  field.value = text;
  field.setAttribute('readonly', '');
  // 不能用 display:none/visibility:hidden——选不中就复制不了，只能挪出视口。
  field.style.cssText = 'position:fixed;top:-1000px;left:0;opacity:0';
  document.body.appendChild(field);

  const selection = document.getSelection();
  const previousRange = selection.rangeCount ? selection.getRangeAt(0) : null;
  field.select();
  field.setSelectionRange(0, text.length);

  try {
    if (!document.execCommand('copy')) throw new Error('copy command rejected');
  } finally {
    document.body.removeChild(field);
    if (previousRange) {
      selection.removeAllRanges();
      selection.addRange(previousRange);
    }
  }
};

/**
 * Writes a text string to the system clipboard.
 *
 * @async
 * @param {string} data text to be written to the clipboard
 * @throws {Error} unable to copy text to clipboard
 */
export const copyTextToClipboard = async data => {
  try {
    const text =
      typeof data === 'object' && data !== null
        ? JSON.stringify(data, null, 2)
        : String(data ?? '');

    // navigator.clipboard 只在安全上下文里存在。仍有同事用 http://<服务器 IP>
    // 访问，那边它是 undefined，全站复制按钮都会报错——降级走旧的选中复制。
    if (navigator.clipboard) {
      await navigator.clipboard.writeText(text);
    } else {
      copyViaSelection(text);
    }
  } catch (error) {
    throw new Error(`Unable to copy text to clipboard: ${error.message}`);
  }
};

/**
 * Handles OTP paste events by extracting numeric digits from clipboard data.
 *
 * @param {ClipboardEvent} event - The paste event from the clipboard
 * @param {number} maxLength - Maximum number of digits to extract (default: 6)
 * @returns {string|null} - Extracted numeric string or null if invalid
 */
export const handleOtpPaste = (event, maxLength = 6) => {
  if (!event?.clipboardData) return null;

  const pastedData = event.clipboardData
    .getData('text')
    .replace(/\D/g, '') // Remove all non-digit characters
    .slice(0, maxLength); // Limit to maxLength digits

  // Only return if we have the exact expected length
  return pastedData.length === maxLength ? pastedData : null;
};
