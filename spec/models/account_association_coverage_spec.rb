require 'rails_helper'

# Guard against the NoMethodError bug class fixed for `crm_exhibitions`.
#
# Controllers under the business namespaces scope queries through the account:
# `Current.account.crm_exhibitions`, `account.mes_products`, and so on. Those
# reads only work if `Account` actually declares the matching `has_many`. Adding
# a model + controller but forgetting the association compiles fine, passes
# review, and then raises `NoMethodError` on the first request → HTTP 500.
#
# That is exactly what happened to `crm_exhibitions` / `crm_exhibition_invites`:
# the 展会 feature shipped with data in production while its list endpoint 500'd,
# because `app/models/account.rb` never declared either association.
#
# This spec greps the app for `<receiver>.<prefix>_something` reads where the
# receiver is an account, and asserts `Account` reflects on each name.
RSpec.describe 'Account association coverage' do
  PREFIXES = %w[crm mes erp oa org tiktok].freeze

  # `account.crm_foo` reads that are genuinely methods, not associations.
  ALLOWED_METHODS = %w[
    crm_performance_setting
  ].freeze

  # Receivers that hold an Account at runtime.
  RECEIVER = /(?:Current\.account|@account|\baccount)/

  def scan_paths
    %w[app lib enterprise].flat_map do |dir|
      Dir.glob(Rails.root.join(dir, '**', '*.rb'))
    end.reject { |f| f.end_with?('app/models/account.rb') }
  end

  it 'declares every account association the app reads through' do
    pattern = /#{RECEIVER}\.((?:#{PREFIXES.join('|')})_\w+)/
    used = Hash.new { |h, k| h[k] = [] }

    scan_paths.each do |file|
      File.read(file).scan(pattern) do
        name = Regexp.last_match(1)
        next if ALLOWED_METHODS.include?(name)

        used[name] << Pathname.new(file).relative_path_from(Rails.root).to_s
      end
    end

    missing = used.reject { |name, _| Account.reflect_on_association(name.to_sym) }

    expect(missing).to be_empty, lambda {
      missing.map { |name, files| "  #{name}  ← #{files.uniq.first(3).join(', ')}" }
             .unshift('Account 上缺少这些关联（调用处会 NoMethodError → 500）：')
             .join("\n")
    }
  end
end
