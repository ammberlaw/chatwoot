# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
Rails.application.config.filter_parameters += [
  :push_token, :registration_id, :device_id, :apns_private_key,
  :password, :secret, :_key, :auth, :crypt, :salt, :certificate, :otp, :access, :private, :protected, :ssn,
  :otp_secret, :otp_code, :backup_code, :mfa_token, :otp_backup_codes
]

# Regex to filter all occurrences of 'token' in keys except for 'website_token'
filter_regex = /\A(?!.*\bwebsite_token\b).*token/i

# Apply the regex for filtering
Rails.application.config.filter_parameters += [filter_regex]
