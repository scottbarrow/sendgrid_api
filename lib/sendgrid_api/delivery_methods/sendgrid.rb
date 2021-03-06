begin
  require 'mail/check_delivery_params'
rescue LoadError
end

module Mail
  class Sendgrid
    include ::Mail::CheckDeliveryParams rescue nil

    attr_accessor :settings, :client, :xsmtp

    def initialize(options={})
      self.settings = {
        api_user: nil,
        api_key: nil
      }.merge!(options)

      @client = SendgridApi::Client.new(self.settings)
    end

    def deliver!(mail)
      check_delivery_params(mail)

      # Extract the recipients, allows array of strings, array of addresses or comma separated string
      to = mail[:to].value
      to = to.split(",").collect(&:strip) if to.is_a? String
      to = Array(to).collect { |to| Mail::Address.new(to) }

      if (mail[:bcc])
        bcc = mail[:bcc].value
        bcc = bcc.split(",").collect(&:strip) if bcc.is_a? String
        bcc = Array(bcc).collect { |bcc| Mail::Address.new(bcc).address }
      end

      # Set the Return-Path header if we have a from email address
      from = Mail::Address.new(mail[:from].value)
      mail.header["Return-Path"] = from.address if mail.header["Return-Path"].nil?

      # Put Reply-To on the headers as Sendgrid Web API only accepts an address
      mail.header["Reply-To"] = Mail::Address.new(mail[:reply_to].value) if (mail[:reply_to])

      # Call .to_s to force into JSON as Mail < 2.5 doesn't
      xsmtp = parse_xsmtpapi_headers(mail)
      @mailer = SendgridApi::Mail.new(@client, xsmtp: xsmtp)

      # Pass everything through, .queue will remove nils
      result = @mailer.queue(
        to:       to.collect(&:address),
        toname:   to.collect(&:name),
        from:     from.address,
        fromname: from.display_name,
        bcc:      bcc,
        subject:  mail.subject,
        text:     mail.text_part.blank? ? nil : mail.text_part.body,
        html:     mail.html_part.blank? ? nil : mail.html_part.body,
        headers:  header_to_hash(mail).to_json
      )
      raise SendgridApi::Error::DeliveryError.new(result.message) if result.error?
      return result
    end

    # Simple check of required Mail params if superclass doesn't exist from 2.5.0
    # @param [Mail] mail
    #
    def check_delivery_params(mail)
      if defined?(super)
        super
      else
        raise ArgumentError.new("Missing required mail part") if (mail.from.blank? || mail.to.blank? || (mail.html_part.blank? && mail.text_part.blank?))
      end
    end

    private

    # Convert Mail::Header fields to Hash and remove specific params
    # @param [Mail] mail
    # @return [Hash]
    #
    def header_to_hash(mail)
      reject_keys = %w(To From Bcc Subject X-SMTPAPI)
      if mail['Content-Type'] && mail['Content-Type'].value.start_with?('multipart/alternative')
        reject_keys.concat %w(Content-Type Mime-Version)
      end
      mail.header_fields.each_with_object(Hash.new) do |field, hash|
        next if reject_keys.include?(field.name)
        hash[field.name] = field.value
      end
    end

    # Extract the ::Mail header['X-SMTPAPI'] value and call SendgridApi::Mail methods to build JSON
    # @param [Mail]
    #
    def parse_xsmtpapi_headers(mail)
      mail.header['X-SMTPAPI'].value.to_s if mail.header['X-SMTPAPI']
    end
  end
end
