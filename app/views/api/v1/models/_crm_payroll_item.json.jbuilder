json.(resource, :id, :user_id, :employee_name, :position, :employment_status,
      :hire_date, :sort_order,
      :base_total_micros, :basic_salary_micros, :position_allowance_micros,
      :seniority_allowance_micros, :meal_allowance_micros, :lodging_allowance_micros,
      :attendance_bonus_micros, :excellent_bonus_micros, :performance_salary_micros,
      :commission_salary_micros,
      :weekday_ot_hours, :weekday_ot_rate_micros, :weekday_ot_pay_micros,
      :weekend_ot_hours, :weekend_ot_rate_micros, :weekend_ot_pay_micros,
      :actual_days, :expected_days, :leave_days, :attendance_pay_micros,
      :late_deduction_micros, :absence_deduction_micros,
      :social_insurance_micros, :income_tax_micros,
      :adjustment_micros, :adjustment_reason,
      :gross_pay_micros, :net_pay_micros, :remark)
# 有没有对上系统账号——没账号的人工资条发不出去，列表上要能看出来。
json.has_account resource.user_id.present?
