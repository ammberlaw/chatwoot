class Oa::ApprovalCcReceipt < ApplicationRecord
  belongs_to :request, class_name: 'Oa::ApprovalRequest'
  belongs_to :user
end
