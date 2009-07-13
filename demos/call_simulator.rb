require 'sinatra' unless defined? Sinatra
require 'twilio/call_handler'
require 'twilio/verb'
require 'builder'

set :public, Proc.new { File.join(root, "call_simulator") }
set :clean_trace, true
set :lock, true

def ns_get(matcher,&block)
  get(Regexp.new('^/call-sim/?'+matcher.to_s+'(\?.*)?$'), &block)
end
def ns_post(matcher,&block)
  post(Regexp.new('^/call-sim/?'+matcher.to_s+'(\?.*)?$'), &block)
end

ns_get "" do
  if not session[:call_handler] or session[:call_handler].phone.call_status == :completed
    session[:call_handler] = Twilio::CallHandler.new
  else
    puts "Triggering a hangup on page reload"
    session[:call_handler].hangup
  end

  ch = session[:call_handler]
  phone = ch.phone

  if params[:call_url]
    ch.call_url(params[:call_url])
  else
    ch.call_url(DEFAULT_URL)
  end

  output = ""
  xml = Builder::XmlMarkup.new(:indent => 2, :target => output)
  xml.instruct!
  xml.declare!(:DOCTYPE, :html, :PUBLIC, "-//W3C//DTD XHTML 1.0 Strict//EN", "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd")

  xml.html(:xmlns=>'http://www.w3.org/1999/xhtml', "xml:lang" => "en") do |xml|
    xml.head do |xml|
      xml.script(:type => "text/javascript", :src => "http://ajax.googleapis.com/ajax/libs/jquery/1.3.2/jquery.min.js") {}
      xml.script(:type => "text/javascript", :src => "/main.js") {}
      xml.link(:type => "text/css", :rel => "stylesheet", :href => "/main.css")
    end
    xml.body do |xml|
      xml.div(:id => "left-sidebar", :class => "sidebar") do |xml|
        xml.form(:id => "call_url", :onsubmit => "ajax_call('call_url'); return false;") do |xml|
          xml.input(:id => 'url', :name => "call_url", :value => "Callback URL");
          xml.button("Call", :type => "submit")#, :onclick => "ajax_call('call_url')")
        end
        xml.div(:id => 'quick_call_links') do |xml|
          [ ["Twilio Welcome",      "http://demo.twilio.com/welcome"                              ],
            ["Naglio Status",       "http://naglio.datadrop.biz/phone_calls/status"               ],
            ["DukeNow",             "http://dukenow-test.heroku.com/twilio/"                      ],
            ["TalkingTexts Inbox",  "http://talkingtexts.datadrop.biz/text_messages/inbox/1.xml"  ],
            ["Earth911 Search",     "http://search.earth911.com/voice/what/?failures=0"           ],
            ["Pause Test",          "http://dreamhost.anselcomputers.com/pause_test.xml"          ],
            ["Twilio Hello World",  "http://demo.twilio.com/helloworld/index.xml"                 ],
            ["Monkey Demo",         "http://dreamhost.anselcomputers.com/hello-monkey.php"        ]
          ].each do |name,url|
            xml.a(name, :href => '#quick_call', :onclick => "$('form#call_url')[0].url.value = #{url.inspect}; ajax_call('call_url'); return false;")
            xml.br
          end
        end
      end
      xml.div(:id => "right-sidebar", :class => "sidebar") do |xml|
        xml.button("Hangup", :id => "hangup", :onclick => "ajax_call('hangup'); return false;");

        xml.div(:id => "countdown", :style => "display:none") {}
        xml.div(:id => "gather_box", :style => "display:none") do |xml|
          xml.button("Timeout", :id => "gather_timeout", :onclick => "ajax_call('gather_timeout'); return false;")
          xml.div(:id => "gather_keypad") do |xml|
            [[1,2,3],[4,5,6],[7,8,9],%w{* 0 #}].each do |row|
              xml.div(:class => "gather_key_row") do |xml|
                row.each do |key|
                  xml.a(key, :class => "gather_key", :href => "#press_digit=#{key}", :onclick => "ajax_call('press_digit', {digit: #{key}}); return false;")
                end
              end
            end
          end
        end
        xml.div(:id => "record_box", :style => "display:none") do |xml|
          xml.button("Timeout", :id => "record_timeout", :onclick => "ajax_call('record_timeout'); return false;")
        end
      end
      xml.button("Toggle Auto-Refresh", :id => "auto_refresh_button", :onclick => "toggle_auto_update_call_flow()")
      xml.div(:id => "call_flow") do |xml|
        xml.div("Call Flow", :class => "call_flow_header")
      end
    end
  end

  output
end

ns_get "/ajax" do
  if session[:call_handler].nil?
    # Reset/Reload page to generate a new session
    return [{:status => false, :method => :reload_page, :params => true}].to_json
    return "<script type='text/javascript'>
            //<![CDATA[
            window.location = window.location;
            //]]> </script>"
  end


  ch = session[:call_handler]
  phone = ch.phone

  case params[:action].downcase
  when 'next'
    #puts "Processing CallHandler queue all the way through"
    true until ch.process_queue.nil?
    #puts "Processing Phone queue all the way through"
    reply = []; h = {:status => true}
    until( h[:noop] or not h[:status] ) do
      h = phone.listen
      s = h[:status]
      m = (h.keys - [:status])[0]
      reply << { :status => s, :method => m, :params => h[m]}
      reply.delete_if{|a| a[:method] == :noop }
    end
    puts "Replying with:\n#{reply.to_yaml}" unless reply == []
    return reply.to_json
  when 'call_url'
    puts "Triggering a hangup so we can make another call"
    ch.hangup
    ch = session[:call_handler] = Twilio::CallHandler.new
    ch.call_url(params[:url])
    return [{:status => true, :method => :notify, :params => "Resetting any previous calls"},
            {:status => false, :method => :call_completed, :params => true},
            {:status => true, :method => :toggle_auto_update_call_flow, :params => true}].to_json
  when 'press_digit'
    accepted = ch.press_digit(params[:digit]) ? "Key press accepted" : "Key press REJECTED!"
    reply = [{:status => true, :method => :notify, :params => accepted}]
    puts "Replying with:\n#{reply.to_yaml}" unless reply == []
    return reply.to_json
  when 'gather_timeout'
    ch.gather_timeout
  when 'record_timeout'
    ch.record_timeout
  when 'hangup'
    session[:call_handler] = Twilio::CallHandler.new
    puts "Triggering a hangup due to AJAX request"
    ch.hangup
    return [{:status => false, :method => :call_completed, :params => true}].to_json
    return "<script type='text/javascript'>
            //<![CDATA[
            call_completed();
            //]]> </script>"
  end

  ""
end
