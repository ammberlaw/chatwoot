# Standalone contract checks for the real controller; no Rails boot, database or mail delivery.
# Run with Ruby >= 3: ruby scripts/test-distributed-mail-reply.rb
require 'minitest/autorun'
require 'set'

module Api
  module V1
    module Accounts
      module Crm
        class BaseController
          def self.before_action(*); end
        end
      end
    end
  end
end
class Current
  class << self
    attr_accessor :account, :account_user
  end
end
module Crm
  class AccessScope
    def initialize(_account, member)
      @member = member
    end
    def mail_visible_owner_ids
      @member.visible
    end
  end
end
load File.expand_path('../app/controllers/api/v1/accounts/crm/emails_controller.rb', __dir__)

class DistributedMailReplyTest < Minitest::Test
  Member = Struct.new(:admin, :deputy, :visible) do
    def administrator? = admin
    def crm_deputy_admin? = deputy
  end
  Customer = Struct.new(:contact_email, :account_owner_id, :shared_user_ids, :account_owner)
  Email = Struct.new(:account_id, :folder, :from_address, :to_address, :cc_address)
  Distribution = Struct.new(:to_user_id, :crm_email)
  Account = Struct.new(:id, :crm_customers, :crm_email_distributions)
  User = Struct.new(:id, :name)
  class Customers
    def initialize(rows)
      @rows = rows
    end
    def where(sql = nil, email = nil)
      return self unless sql
      self.class.new(@rows.select { |row| row.contact_email.strip.downcase == email })
    end
    def not(account_owner_id:)
      self.class.new(@rows.reject { |row| row.account_owner_id == account_owner_id })
    end
    def first = @rows.first
  end
  class Distributions
    include Enumerable
    def initialize(rows)
      @rows = rows
    end
    def to_user(id) = self.class.new(@rows.select { |row| row.to_user_id == id })
    def includes(*) = self
    def each(&block) = @rows.each(&block)
  end
  def setup
    @me = User.new(8, 'Sales')
    @member = Member.new(false, false, [])
    @customers = ['client@example.test', 'peer@example.test', 'client+other@example.test'].map do |email|
      Customer.new(email, 20, [], User.new(20, 'Owner'))
    end
    @distributions = []
  end
  def blocked(addresses = 'client@example.test')
    Current.account = Account.new(1, Customers.new(@customers), Distributions.new(@distributions))
    Current.account_user = @member
    controller = Api::V1::Accounts::Crm::EmailsController.new
    me = @me
    controller.define_singleton_method(:current_user) { me }
    controller.send(:poaching_blocked_recipients, addresses).map { |row| row[:email] }
  end
  def distribute(email, recipient: @me.id)
    @distributions << Distribution.new(recipient, email)
  end
  def incoming(account: 1)
    Email.new(account, 'INBOX', 'Client <CLIENT@example.test>', 'boss@our.test', 'peer@example.test')
  end
  def test_other_customer_remains_blocked_without_distribution
    assert_equal ['client@example.test'], blocked
  end
  def test_distributed_incoming_counterparty_is_allowed_case_insensitively
    distribute(incoming)
    assert_empty blocked('Client <CLIENT@example.test>')
  end
  def test_cc_and_unrelated_customers_are_not_granted_with_the_sender
    distribute(incoming)
    assert_equal ['peer@example.test'], blocked('client@example.test, peer@example.test')
  end
  def test_distribution_to_another_person_does_not_authorize_current_user
    distribute(incoming, recipient: 9)
    assert_equal ['client@example.test'], blocked
  end
  def test_cross_account_association_does_not_grant_access
    distribute(incoming(account: 2))
    assert_equal ['client@example.test'], blocked
  end
  def test_distributed_outgoing_uses_recipient_side_and_not_cc
    distribute(Email.new(1, 'SENT', 'boss@our.test', 'Client <client@example.test>', 'peer@example.test'))
    assert_empty blocked
    assert_equal ['peer@example.test'], blocked('peer@example.test')
  end
  def test_deleted_source_email_grants_no_access
    distribute(nil)
    assert_equal ['client@example.test'], blocked
  end
  def test_address_matching_is_exact
    distribute(incoming)
    assert_equal ['client+other@example.test'], blocked('client+other@example.test')
  end
  def test_existing_owner_share_and_team_rules_still_apply
    @customers[0].account_owner_id = @me.id
    assert_empty blocked
    @customers[0].account_owner_id = 20
    @customers[0].shared_user_ids = [@me.id]
    assert_empty blocked
    @customers[0].shared_user_ids = []
    @member.visible = [20]
    assert_empty blocked
  end
  def test_existing_administrator_rule_still_applies
    @member.admin = true
    assert_empty blocked
  end
end
