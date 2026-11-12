class Oa::ApprovalEvent < ApplicationRecord
  belongs_to :account
  belongs_to :request, class_name: 'Oa::ApprovalRequest'
  belongs_to :actor, class_name: 'User', optional: true
  has_many_attached :files
end
