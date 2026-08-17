json.customer do
  json.partial! 'api/v1/models/crm_customer', formats: [:json], resource: @customer
end

json.opportunities @opportunities do |opportunity|
  json.id opportunity.id
  json.name opportunity.name
  json.amount_micros opportunity.amount_micros
  json.currency opportunity.currency
  json.probability opportunity.probability
  json.sales_stage opportunity.sales_stage
  json.expected_close_date opportunity.expected_close_date
  json.next_action opportunity.next_action
  json.current_need opportunity.current_need
end

json.orders @orders do |order|
  json.id order.id
  json.order_no order.order_no
  json.name order.name
  json.pi_no order.pi_no
  json.order_amount_micros order.order_amount_micros
  json.order_currency order.order_currency
  json.order_date order.order_date
  json.delivery_date order.delivery_date
  json.status order.status
  json.files order.files.map { |f| { id: f.id, filename: f.filename.to_s, url: url_for(f) } }
end

json.pis @pis do |pi|
  json.id pi.id
  json.pi_no pi.pi_no
  json.buyer pi.buyer_company.presence || pi.crm_customer&.name
  json.total_amount_micros pi.total_amount_micros
  json.currency pi.currency
  json.status pi.status
  json.pi_date pi.pi_date
end

json.quotes @quotes do |quote|
  json.id quote.id
  json.quote_no quote.quote_no
  json.name quote.name
  json.total_amount_micros quote.total_amount_micros
  json.quote_currency quote.quote_currency
  json.quote_date quote.quote_date
  json.status quote.status
end

json.notes @notes do |note|
  json.id note.id
  json.title note.title
  json.body note.body
  json.follow_up_method note.follow_up_method
  json.result_tag note.result_tag
  json.owner_name note.owner&.crm_display_name
  json.created_at note.created_at
end

json.tasks @tasks do |task|
  json.id task.id
  json.title task.title
  json.body task.body
  json.due_at task.due_at
  json.status task.status
  json.task_type task.task_type
  json.assignee_name task.assignee&.crm_display_name
end
