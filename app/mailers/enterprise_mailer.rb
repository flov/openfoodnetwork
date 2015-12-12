require 'devise/mailers/helpers'
class EnterpriseMailer < Spree::BaseMailer
  include Devise::Mailers::Helpers

  def welcome(enterprise)
    @enterprise = enterprise
    mail(:to => enterprise.email, :from => from_address,
         :subject => "#{enterprise.name} is now on #{Spree::Config[:site_name]}")
  end

  def confirmation_instructions(record, token, opts={})
    @token = token
    find_enterprise(record)
    mail(subject: "Please confirm your email for #{@enterprise.name}",
         to: ( @enterprise.unconfirmed_email || @enterprise.email ),
         from: from_address)
  end

  private
  def find_enterprise(enterprise)
    @enterprise = enterprise.is_a?(Enterprise) ? enterprise : Enterprise.find(enterprise)
  end
end
