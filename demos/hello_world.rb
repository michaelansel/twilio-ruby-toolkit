require 'sinatra'
require 'twilio/verb'

get Regexp.new("^/$") do
  r = Twilio::Response.new
  r.say("Hello World!")
  r.to_xml
end

post Regexp.new("^/$") do
  r = Twilio::Response.new
  r.say("Hello, new caller!")
  r.to_xml
end
