class Crm::OffboardingRun < ApplicationRecord
  belongs_to :account
  belongs_to :employee, class_name: 'Crm::Employee', optional: true
  belongs_to :actor, class_name: 'User', optional: true
  validates :status, inclusion: { in: %w[pending completed failed] }
end
