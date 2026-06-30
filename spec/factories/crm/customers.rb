# frozen_string_literal: true

FactoryBot.define do
  factory :crm_customer, class: 'Crm::Customer' do
    sequence(:name) { |n| "客户 #{n}" }
    account

    trait :in_public_pool do
      is_in_public_pool { true }
      public_pool_at { Time.current }
    end
  end
end
