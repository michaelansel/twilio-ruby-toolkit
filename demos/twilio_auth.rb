class Rack::TwilioAuth
  require 'twilio'

  def initialize(app)
    @app = app
  end

  def call(env)
    req = env['rack.request'] || Rack::Request.new(env)
    if  req.post? and
        not Twilio::Auth.valid?(req.url(), req.POST(), env['HTTP_X_TWILIO_SIGNATURE'])
      response = Twilio::Response.new
      response.say("Unable to authenticate request. Please try again.")
      [401, {'Content-Type' => 'application/xml'}, response.to_xml]
    else
      @app.call(env)
    end
  end
end
