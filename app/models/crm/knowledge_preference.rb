class Crm::KnowledgePreference < ApplicationRecord
  belongs_to :doc, class_name: 'Crm::KnowledgeDoc'
  belongs_to :user
end
