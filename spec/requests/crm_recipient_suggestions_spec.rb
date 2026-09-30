# frozen_string_literal: true

require 'rails_helper'

# 转发邮件给同事时，收件人联想必须给出同事**实际收信的工作邮箱**。
# 原来给的是登录邮箱——生产上 14 个 CRM 成员里只有 2 个的登录邮箱恰好也是工作邮箱，
# 其余人被选中后邮件会寄到一个没人收信的地址，转发等于石沉大海。
RSpec.describe 'CRM 收件人联想', type: :request do
  let(:account) { create(:account) }
  let(:me) { create(:user, account: account) }
  let!(:colleague) { create(:user, account: account, name: '赵妮娜', email: 'login-only@internal.test') }

  let(:auth) { { api_access_token: me.access_token.token } }

  before { me.account_users.first.update!(crm_role: 'sales') }

  def suggest(query)
    get "/api/v1/accounts/#{account.id}/crm/recipient_suggestions", params: { q: query }, headers: auth
    response.parsed_body
  end

  def add_mailbox(user, address)
    account.crm_mail_accounts.create!(name: address, email_address: address, owner_id: user.id)
  end

  it '给的是同事配置的工作邮箱，不是登录邮箱' do
    add_mailbox(colleague, 'sales23@wintouchgroup.com')
    hit = suggest('赵妮娜').find { |h| h['type'] == 'member' }
    expect(hit['email']).to eq 'sales23@wintouchgroup.com'
    expect(suggest('赵妮娜').pluck('email')).not_to include 'login-only@internal.test'
  end

  it '一个人配了多个邮箱就都列出来' do
    add_mailbox(colleague, 'sales23@wintouchgroup.com')
    add_mailbox(colleague, 'nina@wintouchcn.com')
    expect(suggest('赵妮娜').select { |h| h['type'] == 'member' }.pluck('email'))
      .to contain_exactly('sales23@wintouchgroup.com', 'nina@wintouchcn.com')
  end

  it '没配过邮箱的同事才退回登录邮箱' do
    expect(suggest('赵妮娜').find { |h| h['type'] == 'member' }['email']).to eq 'login-only@internal.test'
  end

  it '按邮箱搜也能命中，且带上本人姓名' do
    add_mailbox(colleague, 'sales23@wintouchgroup.com')
    hit = suggest('login-only').find { |h| h['type'] == 'member' }
    expect(hit).to include('name' => '赵妮娜', 'email' => 'sales23@wintouchgroup.com')
  end
end
