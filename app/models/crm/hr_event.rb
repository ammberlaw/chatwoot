class Crm::HrEvent < ApplicationRecord
  belongs_to :account
  belongs_to :employee, class_name: 'Crm::Employee', optional: true
  belongs_to :department, class_name: 'Org::Department', optional: true
  belongs_to :actor, class_name: 'User', optional: true
  has_many_attached :files

  validates :kind, presence: true

  def self.record!(account:, kind:, employee: nil, department: nil, actor: Current.user, user_id: nil, payload: {}, files: [])
    event = create!(account: account, employee: employee, department: department, actor: actor,
                    user_id: user_id || employee&.user_id, kind: kind, payload: payload)
    event.files.attach(files) if files.any?
    event
  end
end
