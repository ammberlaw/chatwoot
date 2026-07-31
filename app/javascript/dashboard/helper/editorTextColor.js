import MarkdownIt from 'markdown-it';
import { MarkdownParser, MarkdownSerializer } from 'prosemirror-markdown';
import { Schema } from 'prosemirror-model';
import {
  MessageMarkdownTransformer,
  MessageMarkdownSerializer,
} from '@chatwoot/prosemirror-schema';

// 邮件写信的「文字颜色」：ProseMirror 里是 textColor mark，markdown 存储用
// `<span style=color:#rrggbb>…</span>` 标记（不带引号，避开 MessageFormatter
// 的 typographer 弯引号替换）。编辑器、草稿回填、预览/发送 HTML 三端共用这里
// 的序列化/解析规则；发送时后端会把标记从纯文本 part 剥掉。

const HEX_RE = /^#[0-9a-f]{6}$/;

const rgbToHex = value => {
  const m = /^rgba?\((\d+)[,\s]+(\d+)[,\s]+(\d+)/.exec(value);
  if (!m) return null;
  const hex = [m[1], m[2], m[3]]
    .map(n => Number(n).toString(16).padStart(2, '0'))
    .join('');
  return `#${hex}`;
};

// 粘贴进来的 HTML 颜色可能是 rgb(...) / #abc / #aabbcc，统一成 6 位小写 hex。
export const normalizeColor = value => {
  if (!value) return null;
  const v = value.trim().toLowerCase();
  if (HEX_RE.test(v)) return v;
  if (/^#[0-9a-f]{3}$/.test(v))
    return `#${v[1]}${v[1]}${v[2]}${v[2]}${v[3]}${v[3]}`;
  return rgbToHex(v);
};

const textColorMarkSpec = {
  attrs: { color: {} },
  parseDOM: [
    {
      style: 'color',
      getAttrs: value => {
        const color = normalizeColor(value);
        return color ? { color } : false;
      },
    },
  ],
  toDOM: mark => ['span', { style: `color: ${mark.attrs.color}` }, 0],
};

// 下划线 mark：markdown 存储用 <u>…</u> 标记，与 textColor 走同一条序列化通道。
const underlineMarkSpec = {
  parseDOM: [
    { tag: 'u' },
    {
      style: 'text-decoration',
      getAttrs: value => (value.includes('underline') ? {} : false),
    },
  ],
  toDOM: () => ['u', 0],
};

export function addTextColorToSchema(schema) {
  let nodes = schema.spec.nodes;
  // buildMessageSchema 会用 marks 白名单限制段落等节点，新 mark 要补进白名单。
  ['paragraph', 'blockquote', 'heading'].forEach(name => {
    const spec = nodes.get(name);
    if (spec && spec.marks != null) {
      nodes = nodes.update(name, {
        ...spec,
        marks: spec.marks
          ? `${spec.marks} textColor underline`
          : 'textColor underline',
      });
    }
  });
  return new Schema({
    nodes,
    marks: schema.spec.marks
      .addToEnd('textColor', textColorMarkSpec)
      .addToEnd('underline', underlineMarkSpec),
  });
}

export const textColorMarkdownSerializer = new MarkdownSerializer(
  { ...MessageMarkdownSerializer.nodes },
  {
    ...MessageMarkdownSerializer.marks,
    textColor: {
      open: (_state, mark) => `<span style=color:${mark.attrs.color}>`,
      close: '</span>',
      mixable: true,
      expelEnclosingWhitespace: true,
    },
    underline: {
      open: '<u>',
      close: '</u>',
      mixable: true,
      expelEnclosingWhitespace: true,
    },
  }
);

const COLOR_OPEN_RE = /^<span style=color:(#[0-9a-f]{6})>/i;
const COLOR_CLOSE_RE = /^<\/span>/i;
const U_OPEN_RE = /^<u>/i;
const U_CLOSE_RE = /^<\/u>/i;

const colorSpanRule = (state, silent) => {
  if (state.src.charCodeAt(state.pos) !== 0x3c /* < */) return false;
  const src = state.src.slice(state.pos);
  const open = COLOR_OPEN_RE.exec(src);
  if (open) {
    if (!silent) {
      const token = state.push('color_span_open', 'span', 1);
      token.attrSet('color', open[1].toLowerCase());
    }
    state.pos += open[0].length;
    return true;
  }
  const close = COLOR_CLOSE_RE.exec(src);
  if (close) {
    if (!silent) state.push('color_span_close', 'span', -1);
    state.pos += close[0].length;
    return true;
  }
  const uOpen = U_OPEN_RE.exec(src);
  if (uOpen) {
    if (!silent) state.push('u_tag_open', 'u', 1);
    state.pos += uOpen[0].length;
    return true;
  }
  const uClose = U_CLOSE_RE.exec(src);
  if (uClose) {
    if (!silent) state.push('u_tag_close', 'u', -1);
    state.pos += uClose[0].length;
    return true;
  }
  return false;
};

// 与 messageParser.js 的基础 tokenizer 配置一致，仅追加 color_span 规则。
const createTokenizer = () => {
  const md = MarkdownIt('commonmark', { html: false, linkify: false });
  md.enable(['entity', 'escape']);
  md.disable(['table', 'hr', 'heading', 'lheading'], true);
  md.inline.ruler.before('autolink', 'color_span', colorSpanRule);
  return md;
};

export class TextColorMarkdownTransformer extends MessageMarkdownTransformer {
  constructor(schema) {
    super(schema, createTokenizer());
    const base = this.markdownParser;
    this.markdownParser = new MarkdownParser(base.schema, base.tokenizer, {
      ...base.tokens,
      color_span: {
        mark: 'textColor',
        getAttrs: token => ({ color: token.attrGet('color') }),
      },
      u_tag: { mark: 'underline' },
    });
  }
}

// MessageFormatter 以 html:false 渲染，颜色标记会被转义成 &lt;span …&gt; 文本；
// 渲染后按严格格式还原成真正的 span（仅放行 6 位 hex，其他一概不还原）。
export const renderTextColorSpans = html =>
  html
    .replace(
      /&lt;span style=color:(#[0-9a-f]{6})&gt;/gi,
      '<span style="color:$1">'
    )
    .replace(/&lt;\/span&gt;/gi, '</span>')
    .replace(/&lt;u&gt;/gi, '<u>')
    .replace(/&lt;\/u&gt;/gi, '</u>');

// 纯文本场景（列表摘要等）直接剥掉标记。
export const stripTextColorMarkers = text =>
  (text || '')
    .replace(/<span style=color:#[0-9a-f]{6}>/gi, '')
    .replace(/<\/span>/gi, '')
    .replace(/<\/?u>/gi, '');

// 切换选区下划线；光标态切换 storedMark，让后续输入延续/退出下划线。
export function toggleUnderlineMark(editorView) {
  if (!editorView) return;
  const { state } = editorView;
  const markType = state.schema.marks.underline;
  if (!markType) return;
  const { from, to, empty, $from } = state.selection;
  const { tr } = state;
  if (empty) {
    const active = (state.storedMarks || $from.marks()).some(
      m => m.type === markType
    );
    editorView.dispatch(
      active
        ? tr.removeStoredMark(markType)
        : tr.addStoredMark(markType.create())
    );
  } else {
    const has = state.doc.rangeHasMark(from, to, markType);
    editorView.dispatch(
      (has
        ? tr.removeMark(from, to, markType)
        : tr.addMark(from, to, markType.create())
      ).scrollIntoView()
    );
  }
  editorView.focus();
}

// 应用/清除选区颜色；光标态转为 storedMark，让后续输入延续颜色。
export function applyTextColor(editorView, color) {
  if (!editorView) return;
  const { state } = editorView;
  const markType = state.schema.marks.textColor;
  if (!markType) return;
  const { from, to, empty } = state.selection;
  const { tr } = state;
  if (empty) {
    editorView.dispatch(
      color
        ? tr.addStoredMark(markType.create({ color }))
        : tr.removeStoredMark(markType)
    );
  } else {
    editorView.dispatch(
      (color
        ? tr.addMark(from, to, markType.create({ color }))
        : tr.removeMark(from, to, markType)
      ).scrollIntoView()
    );
  }
  editorView.focus();
}
