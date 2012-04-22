require_relative './request_proxy'

## Faraday::Connection middleware for OAuth 
# Usage:
# opt = {
#   key: 'consumer key',
#   secret: 'consumer secret',
#   site: 'resource domain'
# }
# Faraday::Connection.new(opt) do |c|
#   use Faraday::Middleware::OAuthRequest, opt
# end

## Making Requests
# pass user's OAuth info over as headers on requests
# e.g. http.get 'page.json', token: 'token', secret: 'secret'

  
class Faraday::Middleware::OAuthRequest < Faraday::Middleware
  
  def initialize(app, oauth={})
    super(app)
    @consumer = ::OAuth::Consumer.new oauth[:key],oauth[:secret], {
      :site => oauth[:site]
    }
  end
  
  def call(env)
    @user = parse_user_from_headers env
    env[:request_headers].merge! 'Authorization' => oauth(env).header
    @app.call env
  end
  
  private
  
  def parse_user_from_headers(env)
    headers = env[:request_headers]
    { token: headers.delete('Token'), secret: headers.delete('Secret') }
  end
  
  # returns Helper built from @consumer and @user
  def oauth(env)
    ::OAuth::Client::Helper.new env, {
      consumer: @consumer,
      token: ::OAuth::AccessToken.new(@consumer, @user[:token],@user[:secret]),
      request_uri: env[:url]
    }
  end
  
end




