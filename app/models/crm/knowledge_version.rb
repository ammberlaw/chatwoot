class Crm::KnowledgeVersion < ApplicationRecord
  belongs_to :doc, class_name: 'Crm::KnowledgeDoc'
  belongs_to :user, optional: true
  has_many_attached :files
  validates :number, uniqueness: { scope: :doc_id }
end
