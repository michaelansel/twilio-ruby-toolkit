# vim:set ft=ruby: #

# Configuration
require 'active_record'
dbconfig = YAML.load(File.read('config/database.yml'))
ActiveRecord::Base.establish_connection dbconfig['production']


# Applications

#require 'demos/hello_world'
require 'demos/call_simulator'

# Middleware
require 'demos/twilio_auth'
Twilio::AccountSid = ENV['TWILIO_ACCOUNT_SID']
Twilio::AuthToken  = ENV['TWILIO_AUTH_TOKEN']




use Rack::TwilioAuth
#use Rack::Lock
use Rack::Session::Cookie
#use Rack::Session::Pool, :expire_after => 60*60 # expire after 1 hour

run Sinatra::Application
