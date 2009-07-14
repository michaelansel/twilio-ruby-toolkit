module Twilio
  class CallHandler
    def initialize(opts = {})
      @processing_queue = opts[:processing_queue] || (opts[:queue_class] || Array).new
      @output_queue     = opts[:output_queue]     || (opts[:queue_class] || Array).new
      @input_status     = :none
      @input_verb       = nil
      @input_data       = ""
      @cookie           = ""
    end

    ### Processing Queue "API" ###
    # FIXME Not complete
    # replace(ary)    Clear the queue and add elements of ary
    # clear           Remove all objects from the queue
    # <<(obj)         Append obj to the end of the queue
    # empty?          Is the queue completely empty?
    # unshift         Insert obj at the beginning of the queue
    # shift           Remove and return the first object in the queue


    def destroy
      raise NotImplementedError, "destroy is deprecated"
      unless @phone.nil? or @phone.frozen?
        @phone.instance_eval { @queue.clear ; self.freeze }
      end
      self.instance_variables.each do|var|
        eval "#{var} = nil"
      end
      self.freeze
    end

    def output(status = @processing_queue.empty?)
      output = @output_queue.dup.to_a
      @output_queue.clear
      [output,status]
    end

    def queue_empty?
      @processing_queue.empty?
    end

    def process_queue
      #puts "Preparing to process queue"
      #print "@processing_queue:"
      #puts @processing_queue.to_yaml
      puts "@input_status = #{@input_status}"
      return output(false) if [:gather_waiting, :record_waiting].include? @input_status
      return output  if queue_empty?

      puts "Flushed!" if
      catch(:flush) do
        begin
          continue = true
          while continue
            continue = process_response(@processing_queue.shift)
            throw :flush if [:gather_waiting, :record_waiting].include? @input_status
          end
        rescue Exception => e
          STDERR.puts e.to_s
          STDERR.puts e.backtrace
          @output_queue << {:error => "Exception Raised: #{e.to_s}"}
        end
        false
      end
      return output
    end

    def process_response(xml_or_verb_root)
      if xml_or_verb_root.class == String
        begin
          root = Twilio::TwiML.parse(xml_or_verb_root)
          @output_queue << {:parse => root.to_xml}
        rescue Exception => e
          @output_queue << {:parse => xml_or_verb_root}
          @output_queue << {:error => "Unable to parse TwiML (#{e.to_s})"}
          throw :flush
        end
      elsif xml_or_verb_root.class.include? Twilio::Verb
        root = xml_or_verb_root
      elsif [Symbol,Hash].include? xml_or_verb_root.class 
        root = xml_or_verb_root
      elsif xml_or_verb_root.nil?
        throw :flush
      else
        raise ArgumentError, "Invalid input; Not proccessable (#{xml_or_verb_root.inspect})"
      end

      case root
        when Response
          @processing_queue.replace root.children
          @processing_queue << :response_complete

        when Say
          root.loop.to_i.times do
            @output_queue << {:say => { :body => root.body, :voice => root.voice, :language => root.language } }
          end

        when Play
          root.loop.to_i.times do
            @output_queue << {:play => root.body}
          end

        when Gather
          @output_queue << {:gather => root.merged_attributes }
          @input_status = :gather_processing
          @input_verb = root
          ( root.children.concat([:gather_processed]) ).reverse.each do |i|
            @processing_queue.unshift(i)
          end

        # All children of Gather have been processed, waiting for Digits or timeout
        when :gather_processed
          @input_status = :gather_waiting
          @output_queue << {:notify => :gather_waiting}

        when Record
          @output_queue << {:record => root.merged_attributes}
          @input_status = :record_processing
          @input_verb = root
          @processing_queue.unshift(:record_processed)
          # skip straight to :record_processed, no children allowed

        when :record_processed
          @input_status = :record_waiting
          @output_queue << {:notify => :gather_waiting}

        when Dial
          @output_queue << {:error => "Sorry, I don't know how to handle a Dial verb yet!"}

        when Number
          @output_queue << {:error => "Sorry, I don't know how to handle a Number noun yet!"}

        when Redirect
          @output_queue << {:redirect => root.body}

          throw :flush unless valid_uri?(root.body)

          # Add a placeholder so concurrent calls don't try to hang up
          #@processing_queue << :loading

          skip_remainder_of_response()

          if root.method.downcase.to_sym == :post
            resp,uri = _post(root.body)
          else
            resp,uri = _get(root.body)
          end

          if resp.code.to_i == 200
            @processing_queue.unshift resp.body
          else
            @output_queue << {:error => "Request Error (#{resp.code}): #{resp.message}"}
          end
          #@processing_queue.delete(:loading)

        when Pause
          @output_queue << {:pause => root.length}

        when Hangup, :hangup
          @output_queue << {:hangup => "Explicit hangup"}
          print "@output_queue"
          puts @output_queue.to_yaml
          reset
          print "@output_queue"
          puts @output_queue.to_yaml
          throw :flush

        when :response_complete
          if @processing_queue.include? :loading
            puts "Done processing, but waiting for something to load"
          else
            @output_queue << {:hangup => "Finished processing Response"}
            reset
          end
          throw :flush

        when :loading
          puts "Waiting for something to load..."
          print "Processing queue:"
            @processing_queue.to_a.to_yaml

          @processing_queue.unshift :loading
          throw :flush

        when Hash
          case root.keys.first
          when :call_url
            puts "blah blah blah" * 50

          when :press_digits
            root = root[:press_digits]
            unless valid_uri?(root[:verb].action)
              @output_queue << {:error => "Invalid URI: #{root[:verb].action}"}
              throw :flush
            end


            # Skip over any unprocessed elements under the Gather
            if ( root[:status] == :gather_processing ) and ( @processing_queue.index(:gather_processed) >= 0 )
              until( (e=@processing_queue.delete_at(0)) == :gather_processed ) do
                @output_queue << {:skip => e.to_xml(:skip_instruct => true)}
              end
            end

            # Skip the rest of the response; we are done with this TwiML doc
            skip_remainder_of_response();


            @output_queue << {:notify => (root[:verb].method.upcase + "ing to #{root[:verb].action}" +
                            " with params #{ {:Digits => root[:data]}.inspect }") }

            # Submit @input_data to "action" URL
            if root[:verb].method.downcase.to_sym == :post
              method = "POST"
              resp,uri = _post(root[:verb].action, :Digits => root[:data])
            else
              method = "GET"
              resp,uri = _get(root[:verb].action, :Digits => root[:data])
            end

            if resp.code.to_i == 200
              @output_queue << {:notify => "Submitted Gathered Digits: #{method} #{uri.to_s}"}
              @processing_queue.unshift resp.body
            else
              @output_queue << {:notify => ("Request Error (#{resp.code}): #{resp.message}" +
                                "URI: #{uri.to_s} Params: #{ {:Digits => root[:data]}.inspect }")}
            end

          end

        else
          raise StandardError, "Unknown element: #{root.class} -- #{root.inspect}"
      end

      true
    end



    def reset
      puts "Clearing @processing_queue"
      puts caller.length > 5 ? caller[0..5] : caller
      print "Previous contents: "
      puts @processing_queue.to_a.to_yaml
      @processing_queue.clear
      @input_status = :none
      @input_verb = nil
      @input_data = ""
    end

    def call_url(url, params = {})
      puts "Calling URL: #{url}"
      @output_queue << {:calling => url}

      return output unless valid_uri?(url)

      # Add a placeholder so concurrent calls don't try to hang up
      #@processing_queue << :loading #NOTE Should be safe thanks to mutex

      resp,uri = _post(url, params)
      if resp.code.to_i == 200
        puts "Page retrieved successfully:"
        puts resp.body
        @processing_queue << resp.body 
        @processing_queue << :hangup
      else
        @output_queue << {:error => "Request Error (#{resp.code}): #{resp.message}"}
      end
      #@processing_queue.delete(:loading)

      print "@processing_queue"
      puts @processing_queue.to_yaml

      process_queue
    end

    def press_digit(digit)
      #return false if @input_status == :gather_handling # We are already handling the Gather
      puts "Handling digit press (#{digit})"
      puts "@input_status = #{@input_status}"

      unless [:gather_processing, :gather_waiting].include? @input_status
        @output_queue << {:notify => "Keypress REJECTED (#{digit})}"}
        return output
      end

      @input_data << "#{digit}"
      @output_queue << {:notify => "Keypress accepted (#{digit})"}
      return output if @input_data.length < @input_verb.numDigits.to_i

      puts "Done collecting digits"
      @processing_queue.unshift( {:press_digits => {:status => @input_status, :verb => @input_verb, :data => @input_data}} )

      return gather_complete
    end

    def gather_complete(params={})
      @input_status = :none
      @input_verb = nil
      @input_data = ""
      @output_queue << {:gather_complete => {:timeout => (params[:timeout] || false)}}

      return output
    end

    def record_complete(params={})
      @input_status = :none
      @input_verb = nil
      @input_data = ""
      @output_queue << {:record_complete => {:timeout => (params[:timeout] || false)}}

      return output
    end



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
      end_of_response_index = @processing_queue.to_a.index(:response_complete)
      case end_of_response_index
      when -1,nil
        # Shouldn't be possible; just clear the whole queue
        puts "Trying to skip remainder of response when nothing remains in processing_queue!"
        @processing_queue.clear
      when 0
        # We are already at the end of the response, just remove the marker
        @processing_queue.shift
      else
        # One or more elements remain to be processed, notify and remove
        until( (e=@processing_queue.shift) == :response_complete ) do
          puts "Skipping "+e.inspect
          @output_queue << {:skip => e.to_xml(:skip_instruct => true)}
        end
      end
    end

    def valid_uri?(uri_to_test)
      # Confirm that URI is parsable
      begin
        uri = URI.parse(uri_to_test)
      rescue Exception => e
        @output_queue << {:error => {:body => "Unable to parse URI:", :twiml => "#{e.to_s}\n\n#{e.backtrace}" }}
        return false
      end

      # Make sure we have a complete URI
      if uri.host.nil? or uri.port.nil?
        @output_queue << {:error => "Unable to handle relative URI: #{uri.to_s}"}
        return false
      end

      return true
    end
  end
end
