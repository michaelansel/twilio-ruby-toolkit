require 'sinatra' unless defined? Sinatra
require 'twilio/call_handler'
require 'twilio/verb'
require 'builder'
require 'digest'

###### BEGIN HACKS #######
require File.join( File.dirname(__FILE__),'call_simulator','database_queue.rb')

require File.join( File.dirname(__FILE__),'call_simulator','database_mutex.rb')
DatabaseMutex.drop_table! if DatabaseMutex.table_exists?
DatabaseMutex.create_table!
DatabaseMutex.reset_column_information

MutexTimeout = 15 #seconds
MutexPause   = 0.5 #seconds

before do
  # Database Mutex
  if session[:dbq_session_id]
    puts session[:dbq_session_id]
    m = DatabaseMutex.find(:first, :conditions => {:session_id => session[:dbq_session_id]})
    if not m.nil? and (Time.now - m.update_at) < MutexTimeout
      puts "Mutex lock: #{m.inspect}"
      halt "Mutex lock"
    end
    DatabaseMutex.destroy_all(:session_id => session[:dbq_session_id])
    DatabaseMutex.create!(:session_id => session[:dbq_session_id])
  elsif request.url =~ /^\/call-sim\/ajax$/
    session[:dbq_session_id] ||= Digest::SHA1.hexdigest( env.inspect + Time.now.to_s )
    DatabaseMutex.create!(:session_id => session[:dbq_session_id])
  end

  if session[:dbq_session_id]
    print "Existing @processing_queue:"
    puts DatabaseQueue.new(:session_id => session[:dbq_session_id], :queue_name => :processing_queue).to_a.to_yaml
  end
end

def ns_get(matcher,&block)
  get(Regexp.new('^/call-sim/?'+matcher.to_s+'(\?.*)?$'), &block)
end
def ns_post(matcher,&block)
  post(Regexp.new('^/call-sim/?'+matcher.to_s+'(\?.*)?$'), &block)
end
def session_store(params = {})
  if params[:call_handler]
    session[:call_handler] = {}
    %w{@input_status @input_verb @input_data @cookie}.each do |var|
      session[:call_handler][var] = params[:call_handler].instance_eval(var)
    end
  end
end
def session_load(params = {})
  if params[:call_handler] and session[:call_handler]
    return session.delete(:call_handler) if session[:call_handler].class != Hash
    %w{@input_status @input_verb @input_data @cookie}.each do |var|
       params[:call_handler].instance_variable_set(var, session[:call_handler][var])
    end
    session.delete(:call_handler)
  end
end

###### END HACKS #######

set :clean_trace, true
set :lock, true

ns_get "/main.css" do
  send_file File.join(File.dirname(__FILE__), "call_simulator", "main.css")
end
ns_get "/main.js" do
  send_file File.join(File.dirname(__FILE__), "call_simulator", "main.js")
end

ns_get "" do
  if session[:dbq_session_id]
    [:processing_queue,:output_queue].each do|q|
      DatabaseQueue.new(:session_id => session[:dbq_session_id], :queue_name => q).clear
    end
    session.delete(:dbq_session_id)
  end
  if session[:call_handler]
    session.delete(:call_handler)
  end

  output = ""
  xml = Builder::XmlMarkup.new(:indent => 2, :target => output)
  xml.instruct!
  xml.declare!(:DOCTYPE, :html, :PUBLIC, "-//W3C//DTD XHTML 1.0 Strict//EN", "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd")

  xml.html(:xmlns=>'http://www.w3.org/1999/xhtml', "xml:lang" => "en") do |xml|
    xml.head do |xml|
      xml.script(:type => "text/javascript", :src => "http://ajax.googleapis.com/ajax/libs/jquery/1.3.2/jquery.min.js") {}
      #xml.script(:type => "text/javascript", :src => "http://ajax.googleapis.com/ajax/libs/jqueryui/1.7.2/jquery-ui.min.js") {}
      xml.script(:type => "text/javascript", :src => "/call-sim/main.js") {}
      if not params[:call_url].nil?
        xml.script("$.(function(){ ajax_call('call_url', #{{:url => params[:call_url]}.to_json}); });", :type => "text/javascript")
      end
      xml.link(:type => "text/css", :rel => "stylesheet", :href => "/call-sim/main.css")
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

  return output
end

ns_get "/ajax" do
  session[:dbq_session_id] ||= Digest::SHA1.hexdigest( env.inspect + Time.now.to_s )
  pq = DatabaseQueue.new(:queue_name => :processing_queue, :session_id => session[:dbq_session_id])
  oq = DatabaseQueue.new(:queue_name => :output_queue, :session_id => session[:dbq_session_id])
  ch = Twilio::CallHandler.new( :processing_queue => pq, :output_queue => oq )
  session_load(:call_handler => ch)
  #pq,oq = ch.instance_eval { [ @processing_queue, @output_queue ] }
  #print "Processing Queue:"
  #print pq.to_yaml

  case params[:action].downcase
  when 'next'
    output,complete = ch.process_queue

  when 'call_url'
    ch.reset;
    output,complete = ch.call_url(params[:url])

  when 'press_digit'
    output,complete = ch.press_digit(params[:digit])

  when 'gather_timeout'
    output,complete = ch.gather_complete(:timeout => true)

  when 'record_timeout'
    output,complete = ch.record_complete(:timeout => true)

  when 'hangup'
    ch.reset;
    output,complete = [[{:hangup => 'Explicit hangup request'}],true]

  end


  output = output.collect do |o|
    puts "Inconsistent output data!!\n#{output.inspect}\n#{output.to_yaml}\nInvalid Object: #{o.inspect}" if o.keys.length != 1
    k = o.keys.first; v = o[k]
    {:method => k, :params => v}
  end

  output << {:method => :call_complete, :params => true} if complete

  session_store(:call_handler => ch)

  puts "Replying with:\n#{output.to_yaml}"
  puts "Call Handler Size: #{ch.to_yaml.length}"
  puts "Session Size: #{session.to_yaml.length}"
  DatabaseMutex.delete_all(:session_id => session[:dbq_session_id])
  return output.to_json
end
