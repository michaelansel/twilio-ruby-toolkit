require 'rubygems'
begin
  require 'openssl'
rescue LoadError
  require 'ruby-hmac'
end
require 'base64'


module Twilio
  module Auth
    class << self
      def valid?(url, post_data, twilio_sig)
        my_sig = calculate_signature(url, post_data)

        if not (twilio_sig == my_sig)
          puts "Unable to validate signatures!"
          puts "URL: #{url}"
          puts "POST Data: #{post_data.inspect}"
          puts "Calculated Signature:.#{my_sig}..."
          puts "Supplied Signature:...#{twilio_sig}..."
        end

        (twilio_sig == my_sig)
      end

      def calculate_signature(url, post_data)
        raise StandardError, "Twilio::AuthToken not set" unless defined? Twilio::AuthToken

        data = url
        post_vars = post_data.to_a.sort{|a,b| a[0].to_s <=> b[0].to_s}
        post_vars.each do |k,v|
          data += k.to_s + v.to_s
        end

        Base64.encode64(hmac_sha1(Twilio::AuthToken, data)).sub("\n",'')
      end

      private
      def hmac_sha1(key, data)
        if defined? OpenSSL
          OpenSSL::HMAC.digest(OpenSSL::Digest::Digest.new('sha1'), key, data)
        else
          # Use ruby-hmac as a fallback
          "" # Just fail for now
        end
      end
    end
  end
end
