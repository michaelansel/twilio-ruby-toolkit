# vim:set ft=ruby: #

# Applications
#require 'demos/hello_world'
require 'demos/call_simulator'

# Middleware
require 'demos/twilio_auth'

Twilio::AccountSid = TWILIO_ACCOUNT_SID = 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
Twilio::AuthToken = TWILIO_AUTH_TOKEN = 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
DEFAULT_URL = 'http://demo.twilio.com/welcome'



use Rack::TwilioAuth
use Rack::Session::Cookie

run Sinatra::Application
