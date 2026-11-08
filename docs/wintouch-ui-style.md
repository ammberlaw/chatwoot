# Wintouch 界面样式

新页面优先复用现有 `Button`、`Input`、`Dialog`、`Label`，设置页复用 `CrmSettingsLayout`。业务逻辑、权限与接口独立于视觉样式。

## 颜色

- 主操作：`bg-wintouch-yellow text-wintouch-ink`，悬停 `hover:enabled:bg-wintouch-yellow-hover`。主题色在 `tailwind.config.js` 集中定义：黄色 #ffca35、悬停 #f5bd24、文字 #202427。
- 选中状态：黑底白字。共用按钮的 `aria-selected="true"` 自动采用黑色选中样式。
- 次操作：浅灰或透明底、深灰文字；避免将普通操作按钮做成蓝色。
- 标签：浅色底、深色字，圆胶囊。成功沿用 teal，风险和删除沿用 ruby，待处理沿用 amber；保留原来的状态含义和用户自选标签颜色。品牌图标保留品牌原色。

## 圆角与玻璃

- 页面与弹窗：`rounded-3xl`（24px）。内容卡片：`rounded-2xl`（16px）。按钮和输入框：`rounded-xl`（12px）。标签：`rounded-full`。
- 页面外框：`border border-n-weak/70 bg-n-solid-1/80 shadow-wintouch-glass backdrop-blur-2xl backdrop-saturate-150`。
- 弹窗内容使用共用 Dialog 的玻璃表面。表格、正文、输入区域保持足够实底，提高阅读清晰度。
- 阴影采用中性 `shadow-wintouch-glass`，避免主按钮的大面积彩色投影；不要在每层卡片重复叠加模糊。

## 字体与间距

- 页面标题 `text-heading-1`（18px），区块标题 `text-heading-2`（16px），小标题 `text-heading-3`（14px）。
- 字段标签 `text-label`（14px），辅助说明与胶囊标签 `text-label-small`（12px）。不要以任意像素值另设一套字号。
- 常规按钮 36–40px，紧凑工具按钮 32px；保留密集表格场景的紧凑尺寸。
- 优先采用 4/8/12/16/24px 间距：标签与字段 4–8px、同组控件 8–12px、卡片间 16px、主要区块 24px。
- 页面标题靠左；设置表单采用 CrmSettingsLayout 的既有宽度，避免拉成通栏长输入框。
- 操作页继续使用 `min-h-0`、内部滚动及固定分页，避免为了加留白使整页变成长页面。

## 交互

- 保留键盘焦点轮廓、禁用状态、加载状态和原有点击行为。
- 过渡指定颜色、阴影或 transform，通常 150ms，避免 `transition-all`；尊重减少动态效果偏好。
- 图标、标签与实际功能保持对应；危险操作保留红色提示，不能为了统一而抹掉语义。
