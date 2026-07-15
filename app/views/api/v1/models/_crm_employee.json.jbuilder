json.id resource.id
json.employee_no resource.employee_no
json.name resource.name
json.gender resource.gender
json.id_card_no resource.id_card_no
json.birth_date resource.birth_date
json.native_place resource.native_place
json.department_id resource.department_id
json.department_name resource.department&.name
json.job_title resource.job_title
json.job_category resource.job_category
json.work_location resource.work_location
json.status resource.status
json.hire_date resource.hire_date
json.regular_date resource.regular_date
json.probation_months resource.probation_months
json.contract_start_date resource.contract_start_date
json.contract_end_date resource.contract_end_date
json.contract_type resource.contract_type
json.renew_count resource.renew_count
json.salary_note resource.salary_note
json.bank_card_no resource.bank_card_no
json.bank_name resource.bank_name
json.phone resource.phone
json.email resource.email
json.wechat resource.wechat
json.resign_date resource.resign_date
json.resign_reason resource.resign_reason
json.resign_type resource.resign_type
json.photo_url resource.photo.attached? ? url_for(resource.photo) : nil
json.entry_files(resource.entry_files.map { |f| { id: f.id, filename: f.filename.to_s, byte_size: f.byte_size, url: url_for(f) } })
json.resign_files(resource.resign_files.map { |f| { id: f.id, filename: f.filename.to_s, byte_size: f.byte_size, url: url_for(f) } })
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i
