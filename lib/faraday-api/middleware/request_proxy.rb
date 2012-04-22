require 'cgi'

module Faraday::API::Middleware
  class RequestProxy < OAuth::RequestProxy::Base

    proxies Hash
    
    def method
      request[:method].to_s.upcase
    end

    def uri
      options[:uri].to_s
    end

    def parameters
      post_parameters.merge(query_parameters).merge(options[:parameters] || {})
    end

    private

    def query_parameters
      query = Addressable::URI.parse(uri).query
      query ? CGI.parse(query) : {}
    end

    def post_parameters
      # Post params are only used if posting form data
      if method == 'POST'
        OAuth::Helper.stringify_keys(request[:body] || {})
      else
        {}
      end
    end
  end
end

