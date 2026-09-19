require 'rails_helper'

# Guard against the Pundit::NotDefinedError bug class.
#
# Every custom controller under the CRM/MES/OA/ORG namespaces uses a bare
# `before_action :check_authorization`, and `check_authorization` calls
# `authorize(SomeModel)` in class form. Pundit then infers the policy query
# method from the action name (`"#{action_name}?"`). If a controller adds a
# custom route action (anything beyond Pundit's ApplicationPolicy defaults —
# e.g. `stage_blob`, `move_to_folder`, `complete_follow_up`) but its policy
# class does not define the matching `<action>?` method, Pundit raises
# `Pundit::NotDefinedError` at runtime → HTTP 500 → a generic "失败" toast.
#
# This spec walks the routes for those namespaces, resolves the policy each
# controller authorizes against, and asserts the `<action>?` method exists.
#
# Assumption: in-scope controllers use a bare `before_action :check_authorization`
# (no `only:`/`except:`). Controllers that authorize manually (no `authorize()`
# call) are auto-skipped. If a future controller narrows check_authorization with
# `only:`/`except:`, add it to SKIP_ACTIONS below.
RSpec.describe 'CRM/MES custom action Pundit policy coverage' do
  NAMESPACE_PREFIXES = %w[
    api/v1/accounts/crm
    api/v1/accounts/mes
    api/v1/accounts/oa
    api/v1/accounts/org
    api/v1/accounts/erp
  ].freeze

  # (controller_path, action) pairs to skip — e.g. actions excluded from
  # check_authorization via only:/except:. Empty today.
  SKIP_ACTIONS = [].freeze

  # A controller can pin the permission it checks — `authorize(X, :index?)` — in which
  # case every action of that controller runs the pinned query, never `<action>?`.
  # Returns the pinned query symbol, or nil when the query follows the action name.
  def self.pinned_query_for(controller_class)
    src = check_authorization_source(controller_class)
    return nil if src.nil?

    src.match(/authorize\(\s*[A-Za-z0-9_:]+\s*,\s*:(\w+\?)/)&.captures&.first&.to_sym
  end

  # Read a controller's check_authorization source and return the policy class it
  # authorizes against (honouring an explicit `policy_class:`), or nil for
  # manual-guard controllers that never call `authorize(...)`.
  def self.policy_for(controller_class)
    return nil unless controller_class.method_defined?(:check_authorization) ||
                      controller_class.private_method_defined?(:check_authorization)

    src = check_authorization_source(controller_class)
    return nil if src.nil?

    if (m = src.match(/policy_class:\s*([A-Za-z0-9_:]+)/))
      m[1].constantize
    elsif (m = src.match(/authorize\(\s*([A-Za-z0-9_:]+)/))
      "#{m[1]}Policy".constantize
    end
  rescue StandardError
    nil
  end

  def self.check_authorization_source(controller_class)
    file, line = controller_class.instance_method(:check_authorization).source_location
    return nil unless file

    File.readlines(file)[(line - 1)..(line + 8)].to_a.join
  rescue StandardError
    nil
  end

  routes = Rails.application.routes.routes.filter_map do |route|
    controller = route.defaults[:controller]
    action = route.defaults[:action]
    next unless controller && action
    next unless NAMESPACE_PREFIXES.any? { |ns| controller.start_with?(ns) }

    [controller, action]
  end.uniq

  routes.each do |controller_path, action|
    next if SKIP_ACTIONS.include?([controller_path, action])

    it "#{controller_path}##{action} has a matching policy method" do
      controller_class = "#{controller_path.camelize}Controller".constantize
      policy = self.class.policy_for(controller_class)

      skip 'manual-guard controller (no Pundit authorize)' if policy.nil?

      # A pinned query (`authorize(X, :index?)`) is what actually runs for every action here.
      query = self.class.pinned_query_for(controller_class) || :"#{action}?"

      expect(policy.method_defined?(query)).to be(true),
                                               "#{policy}##{query} is missing → " \
                                               'Pundit::NotDefinedError → HTTP 500 at runtime'
    end
  end
end
