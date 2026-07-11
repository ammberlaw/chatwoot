class Crm::SendEmailJob < ApplicationJob
  queue_as :medium

  def perform(email_id)
    email = Crm::Email.find_by(id: email_id)
    return unless email&.send_status == 'PENDING'

    Crm::EmailSendService.new(email: email).perform
  end
end
