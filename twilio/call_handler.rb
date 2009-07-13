module Twilio
  class CallHandler
    # Works like a model
    attr_accessor :phone

    def initialize(opts = {})
      if opts[:phone]
        @phone = opts[:phone]
      else
        @phone = Twilio::Phone.new
        @phone.call_handler = self
      end

      @processing_queue = []
      @input_status = :none
      @input_verb = nil
      @input_data = ""
      @cookie = ""
    end

    def clear_queue
      @processing_queue.clear
      @processing_queue = []
    end

    def queue_empty?
      @processing_queue.empty?
    end

    def process_queue
      return nil if [:gather_waiting, :record_waiting].include? @input_status
      return nil if queue_empty?

      process_response(@processing_queue.shift)
    end

    def process_response(xml_or_verb_root)
      if xml_or_verb_root.class == String
        begin
          root = Twilio::TwiML.parse(xml_or_verb_root)
          @phone.parse root.to_xml
        rescue Exception => e
          @phone.parse xml_or_verb_root
          @phone.notify "Unable to parse TwiML (#{e.to_s})"
          puts "Triggering a hangup on TwiML parsing failure"
          hangup
          raise e
        end
      elsif xml_or_verb_root.class.include? Twilio::Verb
        root = xml_or_verb_root
      elsif xml_or_verb_root.class == Symbol
        root = xml_or_verb_root
      elsif xml_or_verb_root.nil?
        return false
      else
        raise ArgumentError, "Invalid input; not a Verb or String (#{xml_or_verb_root.inspect})"
      end

      case root
        when Response
          @processing_queue.unshift :response_complete
          root.children.reverse.each{|c| @processing_queue.unshift(c) }

        when Say
          root.loop.to_i.times do
            @phone.say(root.body, hash_select(root.valid_attributes, :voice, :language))
          end

        when Play
          root.loop.to_i.times do
            @phone.play root.body
          end

        when Gather
          @phone.gather(root.merged_attributes)
          @input_status = :gather_processing
          @input_verb = root
          @processing_queue.unshift(:gather_processed)
          root.children.reverse.each{|c| @processing_queue.unshift(c) }

        # All children of Gather have been processed, waiting for Digits or timeout
        when :gather_processed
          @input_status = :gather_waiting
          @phone.notify "Waiting for Digits or timeout (Gather)..."

        when Record
          @phone.record(root.merged_attributes)
          @input_status = :record_processing
          @input_verb = root
          @processing_queue.unshift(:record_processed)
          # skip straight to :record_processed, no children allowed

        when :record_processed
          @input_status = :record_waiting
          @phone.notify "Waiting for timeout (Record)..."

        when Dial
          @phone.notify "Sorry, I don't know how to handle a Dial verb yet!"

        when Number
          @phone.notify "Sorry, I don't know how to handle a Number noun yet!"

        when Redirect
          @phone.redirect root.body

          return unless valid_uri?(root.body)

          # Add a placeholder so concurrent calls don't try to hang up
          @processing_queue << :loading

          skip_remainder_of_response()

          if root.method.downcase.to_sym == :post
            resp,uri = _post(root.body)
          else
            resp,uri = _get(root.body)
          end

          if resp.code.to_i == 200
            @processing_queue.unshift resp.body
          else
            @phone.notify "Request Error (#{resp.code}): #{resp.message}"
          end
          @processing_queue.delete(:loading)

        when Pause
          @phone.pause(root.length)

        when Hangup, :hangup
          puts "Triggering a hangup on parsing #{root.class} -- #{root}."
          hangup

        when :response_complete
          if @processing_queue.include? :loading
            puts "Done processing, but waiting for something to load"
          else
            puts "Triggering a hangup on :response_complete"
            hangup
          end

        when :loading
          puts "Waiting for something to load..."
          @processing_queue.unshift :loading
          return nil

        else
          raise StandardError, "Unknown element: #{root.class} -- #{root.inspect}"
      end

      true
    end



    def hangup(opts = {})
      puts "Hangup received; Resetting state..."

      #gathering = [:gather_waiting, :gather_processing].include? @input_status
      #recording = [:record_waiting, :record_processing].include? @input_status

      clear_queue()
      #@phone.clear_queue();
      initialize(:phone => @phone)

      #@phone.gather_complete if gathering
      #@phone.record_complete if recording

      @phone.hangup#(:silent => opts[:silent])
    end

    def call_url(url, params = {})
      puts "Calling URL: #{url}"
      @phone.call url

      return unless valid_uri?(url)

      # Add a placeholder so concurrent calls don't try to hang up
      @processing_queue << :loading

      resp,uri = _post(url, params)
      if resp.code.to_i == 200
        @processing_queue << resp.body 
        @processing_queue << :hangup
      else
        @phone.notify "Request Error (#{resp.code}): #{resp.message}"
      end
      @processing_queue.delete(:loading)
    end

    def press_digit(digit)
      #return false if @input_status == :gather_handling # We are already handling the Gather
      return false unless [:gather_processing, :gather_waiting].include? @input_status
      @input_data << "#{digit}"
      return true if @input_data.length < @input_verb.numDigits.to_i

      # Save the input variables so we can reset them
      input_status,input_verb,input_data = @input_status,@input_verb,@input_data

      # We are resetting now so that the "gather_complete" notification
      # goes out without having to wait for the next response.
      #     Faster response == better user experience
      #
      # Reset input variables and notify phone gather is complete
      self.gather_complete

      # Block this out from being launched multiple times
      #@input_status = :gather_handling

      return unless valid_uri?(input_verb.action)


      # Add a placeholder so concurrent calls don't try to hang up
      @processing_queue << :loading

      # Skip over any unprocessed elements under the Gather
      if ( input_status == :gather_processing ) and ( @processing_queue.index(:gather_processed) >= 0 )
        until( (e=@processing_queue.delete_at(0)) == :gather_processed ) do
          @phone.skip e.to_xml(:skip_instruct => true)
        end
      end

      # Skip the rest of the response; we are done with this TwiML doc
      skip_remainder_of_response();


      @phone.notify(input_verb.method.upcase + "ing to #{input_verb.action}" +
                    " with params #{ {:Digits => input_data}.inspect }")

      # Submit @input_data to "action" URL
      if input_verb.method.downcase.to_sym == :post
        method = "POST"
        resp,uri = _post(input_verb.action, :Digits => input_data)
      else
        method = "GET"
        resp,uri = _get(input_verb.action, :Digits => input_data)
      end

      if resp.code.to_i == 200
        @phone.notify("Submitted Gathered Digits: #{method} #{uri.to_s}")
        @processing_queue.unshift resp.body
      else
        @phone.notify "Request Error (#{resp.code}): #{resp.message}" +
          "URI: #{uri.to_s} Params: #{ {:Digits => input_data}.inspect }"
      end
      @processing_queue.delete(:loading)

      return true
    end

    # Reset input variables and notify phone we are done Gathering
    def gather_complete
      @input_status = :none
      @input_verb = nil
      @input_data = ""
      @phone.gather_complete
    end
    alias :gather_timeout :gather_complete

    # Reset input variables and notify phone we are done Recording
    def record_complete
      @input_status = :none
      @input_verb = nil
      @input_data = ""
      @phone.record_complete
    end
    alias :record_timeout :record_complete



    private
    def twilio_sig_header(url, post_data)
      { 'X-Twilio-Signature' => Twilio::Auth.calculate_signature(url, post_data) }
    end

    def _post(url, params = {})
      require 'net/http'
      uri = URI.parse(url.strip)
      post_data = { 'Caller' => '1234567890', 'Called' => '1928374650' }.merge(params)
      uri.query = nil if uri.query == ''


      found = false
      until found
        resp = Net::HTTP.start(uri.host, uri.port) { |http|
          req = Net::HTTP::Post.new(uri.request_uri, twilio_sig_header(uri.to_s, post_data))
          req['Cookie'] = @cookie
          req.form_data = post_data
          http.request(req)
        }
        @cookie = resp['Set-Cookie'] if resp['Set-Cookie']
        resp.header['location'] ? uri = URI.parse(resp.header['location']) : found = true
        puts "Following header redirect to #{uri.to_s}" unless found == true
      end

      [resp, uri]
    end

    def hash_to_query(hash)
      hash.keys.inject('') do |query_string, key|
        query_string << '&' unless key == hash.keys.first
        query_string << "#{URI.encode(key.to_s)}=#{URI.encode(hash[key])}"
      end
    end

    def _get(url, params = {})
      require 'net/http'
      uri = URI.parse(url.strip)

      found = false
      until found
        params = { 'Caller' => '1234567890', 'Called' => '1928374650' }.merge(params)
        uri.query = hash_to_query(params)
        uri.query = nil if uri.query == ''

        resp = Net::HTTP.start(uri.host, uri.port) { |http|
          req = Net::HTTP::Get.new(uri.request_uri, twilio_sig_header(uri.to_s, {}))
          req['Cookie'] = @cookie
          http.request(req)
        }
        @cookie = resp['Set-Cookie'] if resp['Set-Cookie']
        resp.header['location'] ? uri = URI.parse(resp.header['location']) : found = true
        puts "Following header redirect to #{uri.to_s}" unless found == true
      end

      [resp, uri]
    end

    def hash_select(hash,*keys)
      keys.flatten!
      hash.inject({}){|p,kv|
        (keys.include?(kv[0])) ? p.merge({kv[0]=>kv[1]}) : p
      }
    end

    def skip_remainder_of_response()
      # Clear the rest of the current response from the queue
      end_of_response_index = @processing_queue.index(:response_complete)
      case end_of_response_index
      when -1
        # Shouldn't be possible; just clear the whole queue
        @processing_queue = []
      when 0
        # We are already at the end of the response, just remove the marker
        @processing_queue.delete_at(0)
      else
        # One or more elements remain to be processed, notify and remove
        until( (e=@processing_queue.delete_at(0)) == :response_complete ) do
          @phone.skip e.to_xml(:skip_instruct => true)
        end
      end
    end

    def valid_uri?(uri_to_test)
      # Confirm that URI is parsable
      begin
        uri = URI.parse(uri_to_test)
      rescue Exception => e
        @phone.notify "Unable to parse URI:"
        @phone.twiml  "#{e.to_s}\n\n#{e.backtrace}"
        puts "Hanging up because we can't parse the Redirect URI"
        hangup
        return false
      end

      # Make sure we have a complete URI
      if uri.host.nil? or uri.port.nil?
        @phone.notify "Unable to handle relative URI: #{uri.to_s}"
        puts "Hanging up because we don't know how to handle relative URIs yet"
        hangup
        return false
      end

      return true
    end
  end
end
