// 生产订单下拉的搜索内容：单号/产品名之外，再把**销售订单号和客户名**算进去。
// 生产端问得最多的是「这张销售订单的货在哪」，只按 MO 号搜就等于让人自己去对照表。
// 用于 ComboBox 的 option.searchText（本地搜索会把 label 和它一起匹配）。
//
// 这里读的是下划线字段：这些页面都是裸 axios 取生产订单，不走 camelcaseKeys 的 store。
export const orderSearchText = order =>
  [order?.sales_order_no, order?.customer_name].filter(Boolean).join(' ');

export default orderSearchText;
