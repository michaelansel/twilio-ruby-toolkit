require 'json'

module Twilio
  class Phone
    # Works like a controller
    attr_writer :call_handler
    attr_accessor :call_status

    def initialize
      @queue = []
      @call_handler = nil
      @call_status = :in_progress
    end

    def clear_queue
      @queue.clear
      @queue = []
    end

    def say(text_to_say, params = {})
      #params = Twilio::Say.default_attributes.merge(params)
      @queue << [:say, text_to_say, params]
    end

    def play(url_to_play, params = {})
      #params = Twilio::Play.default_attributes.merge(params)
      @queue << [:play, url_to_play, params]
    end

    def gather(params = {})
      #params = Twilio::Gather.default_attributes.merge(params)
      @queue << [:gather, nil, params]
    end

    def gather_complete
      @queue << [:gather_complete, nil, {}]
    end

    def record(params = {})
      #params = Twilio::Record.merged_attributes.merge(params)
      @queue << [:record, nil, params]
    end

    def record_complete
      @queue << [:record_complete, nil, {}]
    end

    def pause(length)
      @queue << [:pause, nil, {:length => length}]
    end

    def hangup(params={})
      @queue << [:hangup, nil, params]
    end

    def call(url)
      notify "Calling <a href=#{url.inspect} onclick=\"$('form#call_url')[0].url.value = $(this)[0].href; ajax_call('call_url'); return false;\">#{url}</a>"
    end
    def redirect(url)
      notify "Redirecting to <a href=#{url.inspect} onclick=\"$('form#call_url')[0].url.value = $(this)[0].href; ajax_call('call_url'); return false;\">#{url}</a>"
    end

    def notify(message)
      @queue << [:notify, message, {}]
    end

    def twiml(xml)
      @queue << [:twiml, xml, {}]
    end

    def parse(xml)
      @queue << [:notify, div("Parsing XML Response:") + div(xml, :class => 'twiml'), {}]
    end

    def skip(xml)
      @queue << [:notify, div("Not processing XML:") + div(xml, :class => 'twiml'), {}]
    end


    def listen
      action,body,params = @queue.shift
      case action
      when nil
        # Just skip it if possible
        return listen unless @queue.empty?

        # Try to jumpstart the processing queue
        @call_handler.process_queue

        if not @queue.empty?
          # Just needed a jumpstart; try again
          return listen
        end

        if not @call_handler.queue_empty?
          # Call not complete (probably waiting for input)
          return {:status => true, :noop => true}
        end

        # So, now that both queues are empty:

        if @call_status == :completed
          # Call completed, send a NOOP
          return {:status => false, :noop => true}

        else
          # Nothing left to do, reset the call handler and mark the call as completed
          # NOTE Should be handled by explicit hangups, but this is here just in case
          puts "Triggering a hangup because we are out of things to do"
          @call_handler.hangup
          @call_status = :completed
          @call_handler.phone = self.class.new # Just create a new stinkin' phone!
          @call_handler.phone.call_handler = @call_handler
          #self.instance_eval { def listen ; raise StandardError, "Call has already ended. Unable to listen anymore." ; end }
          #return [false, div("Implicit hang up (nothing left to do)") + listen[1]]
          #raise StandardError, "Raisin' Cain!"
          #return {:status => false, :notify => "Implicit hang up (nothing left to do)"}
          return {:status => false, :call_completed => true};

        end

      when :hangup
        @call_status = :completed
        #[false, ( params[:silent] ? "" : div("Call ended") ) + javascript("call_completed();")]
        {:status => false, :call_completed => true}

      when :say
        #[true, javascript("say(#{body.inspect});")]
        {:status => true, :say => body}

      when :play
        #[true, javascript("play(#{body.inspect});")]
        {:status => true, :play => body}

      when :gather
        #[true, javascript("gather( #{params[:timeout]} );")]
        {:status => true, :gather => params[:timeout]}

      when :gather_complete
        #[true, javascript("gather_complete();")]
        {:status => true, :gather_complete => true}

      when :record
        #focus [true, div("Recording") + javascript("record(#{params[:timeout]})")]
        {:status => true, :record => params[:timeout]}

      when :record_complete
        #[true, javascript("record_complete();")]
        {:status => true, :record_complete => true}

      when :pause
        #[true, javascript("pause(#{params[:length]})")]
        {:status => true, :pause => params[:length]}

      when :twiml
        #focus [true, div(body, :class => 'twiml')]
        {:status => true, :twiml => body}

      when :notify
        #focus [true, "<div class='notify'>#{body}</div>"]
        {:status => true, :notify => body}

      else
        #focus [true, div("Unknown action (#{action}): #{[action,body,params].inspect}")]
        {:status => true, :notify => "Unknown action (#{action}): #{[action,body,params].inspect}"}

      end
    end

    private
    def javascript(code)
"<script type='text/javascript'>
//<![CDATA[
#{code}
//]]>
</script>"
    end
    def div(content, params={})
      output = ""
      xml = Builder::XmlMarkup.new(:indent => 2, :target => output)
      xml.div(content, params)

      output
    end
    def focus(response)
      [response[0], response[1] + javascript('$("#call_flow > div:last-child")[0].scrollIntoView(true);')]
    end
  end
end
