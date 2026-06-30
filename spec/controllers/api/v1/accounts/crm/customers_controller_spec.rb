require 'rails_helper'

RSpec.describe 'CRM Customers API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/{account.id}/crm/customers' do
    let!(:customer) { create(:crm_customer, account: account, customer_status: 'FOLLOWING') }
    let!(:pool_customer) { create(:crm_customer, :in_public_pool, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/crm/customers"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'returns all customers' do
        get "/api/v1/accounts/#{account.id}/crm/customers",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['meta']['count']).to eq(2)
      end

      it 'filters by public pool' do
        get "/api/v1/accounts/#{account.id}/crm/customers?filter=public_pool",
            headers: agent.create_new_auth_token,
            as: :json

        ids = response.parsed_body['payload'].pluck('id')
        expect(ids).to contain_exactly(pool_customer.id)
      end

      it 'does not leak customers from other accounts' do
        create(:crm_customer, account: create(:account))

        get "/api/v1/accounts/#{account.id}/crm/customers",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response.parsed_body['meta']['count']).to eq(2)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/crm/customers' do
    it 'creates a customer' do
      expect do
        post "/api/v1/accounts/#{account.id}/crm/customers",
             params: { customer: { name: '深圳某外贸公司', customer_status: 'PROSPECT', trade_country: 'USA' } },
             headers: agent.create_new_auth_token,
             as: :json
      end.to change(Crm::Customer, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['name']).to eq('深圳某外贸公司')
    end

    it 'rejects an invalid select value' do
      post "/api/v1/accounts/#{account.id}/crm/customers",
           params: { customer: { name: 'x', customer_status: 'NOT_A_STATUS' } },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/crm/customers/{id}' do
    let!(:customer) { create(:crm_customer, account: account) }

    it 'updates the customer' do
      patch "/api/v1/accounts/#{account.id}/crm/customers/#{customer.id}",
            params: { customer: { customer_level: 'A' } },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(customer.reload.customer_level).to eq('A')
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/crm/customers/{id}' do
    let!(:customer) { create(:crm_customer, account: account) }

    it 'forbids agents from deleting' do
      delete "/api/v1/accounts/#{account.id}/crm/customers/#{customer.id}",
             headers: agent.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'allows administrators to delete' do
      delete "/api/v1/accounts/#{account.id}/crm/customers/#{customer.id}",
             headers: admin.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:success)
      expect(Crm::Customer.exists?(customer.id)).to be(false)
    end
  end
end
