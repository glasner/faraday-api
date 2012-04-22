module Faraday
  # mixin to create API connection
  # creates Class#resource to setup Faraday::Connection
  # see Basecamp::API for an example
  module API
    extend ActiveSupport::Concern

    included do
      ## Faraday
      # only used inside class and for testing
      class << self; attr_accessor :http; end

      ## URL
      # base URL of API
      class << self; attr_accessor :url; end

      ## Services
      # hash of paths setup using Class.resource
      class << self; attr_accessor :services; end

      ## Responses
      # API::Responses loaded from yaml file
      class << self; attr_accessor :responses; end
      self.responses = API::Responses.new(self)


    end

    module ClassMethods
      ## Resource Setup
      # call to setup API connection to given url
      ### Authentication
      # basic: pass opt[:auth] = ['username','password']
      # token: pass opt[:auth] = { :param_name => 'token' }
      # oauth: pass opt[:oauth] = { key: 'app key',secret: 'app secret'}
      ### Services
      # pass hash of services. Values can either be:
      # 1. string path (with or without expansion ala routes)
      # 2. hash with default params and :path key
      ### Faraday Params
      # remaining keys in opt passed directly to Faraday
      def resource(url,opt={})
        auth = opt.delete :auth
        oauth = opt.delete :oauth
        self.services = opt.delete :services
        self.url = url
        opt[:url] = url
        # add params from other keys
        opt[:params] ||= {}
        opt[:params].merge! auth if auth and auth.is_a? Hash
        self.http = Faraday::Connection.new(opt) do |c|
          c.adapter  :typhoeus
          if oauth.present?
            c.use Faraday::Middleware::OAuthRequest, oauth.merge(site: url) 
          end
        end
        http.basic_auth(*auth) if auth and auth.is_a? Array
      end

      ## Request Methods
      # shortcuts for accessing Faraday::Connection
      # http should never be accessed outside of module
      
      def get(path,params={})
        get_request path, params
      end
      
      def get_request(path,params={})
        debug = params.delete :debug
        path = expand path,params
        path = params.empty? ? path : with_query_string(path,params)
        SEER.apilog "[#{self.class}] GET #{self.url}"
        if params[:oauth]
          response = http.get path, params.delete(:oauth)
        else
          response = http.get path
        end
        SEER.log(debug: "API Response: #{response.status} => #{response.body}") if debug
        return response if response.status != 200
        parsed = parse response.body
        block_given? ? yield(parsed) : parsed
        rescue Yajl::ParseError
          raise Faraday::API::ParseError, response
      end
      
      def post(path,body={})
        post_request path, body
      end

      def post_request(path,body={})
        path = expand path
        SEER.apilog "[#{self.class}] POST #{path} BODY(#{body.inspect})"
        if body.is_a?(Hash) and body[:oauth]
          oauth = body.delete :oauth
          response = http.post path, body.to_query,oauth
        else
          params = case body.class.to_s
            when 'Hash' then body.to_query
            when 'Array' then Yajl.dump(body)
            else body
          end
          response = http.post path, params
        end
        return response if response.status != 200 # TODO Need more granular error trapping
        parsed = parse response.body
        block_given? ? yield(parsed) : parsed
        rescue Yajl::ParseError
          raise Faraday::API::ParseError, response
      end

      # appends params as query string to given path
      def with_query_string(path,params)
        start = path.include?('?') ? '&' : '?'
        path + start + params.to_query
      end

      ### Paths
      # can either be standard or string or symbol for key in @@services hash
      # all placeholders, e.g. :id, are expanded from params
      # all placeholders, e.g. :id, are expanded from params
      def expand(path,params={})
        return path unless path.is_a? Symbol
        service = services[path]
        raise Faraday::API::UnknownService if service.nil?
        if service.is_a? Hash
          path = service[:path] || ''
          params.merge! service.except(:path)
        else
          path = service
        end
        path.include?(':') ? expand_placeholders(path,params) : path
      end

      def expand_placeholders(path,params={})
        # creates hash of placeholders with values from params
        # !! removes key from params so they're not passed to API
        placeholders = path.match(/:([^\/\.]+)/).to_a[1..-1].inject({}) do |out,placeholder|
          key = placeholder.to_sym
          out[key] = params.delete key
          out
        end
        # replaces placeholders with values from above
        placeholders.inject(path) { |out, pair| out.gsub ":#{pair[0]}",pair[1].to_s  }
      end

      ## Response

      # returns Nokogiri::XML::Document, Hash, or raw String
      def parse(raw)
        begin
          raw[2..4].eql?('xml') ? Nokogiri::XML(raw) : Yajl.load(raw)
        rescue Yajl::ParseError
          raw
        end
      end

      ### Test Responses
      # returns test responses from api/responses.yml
      # see API::Responses for details
      # def responses
      #   @responses ||= API::Responses.new(self)
      # end
      #

      ## Updated
      # defaults to true for all APIs
      # override with method to check if data has been updated
      def updated?; true;end

    end
    
    class Error < StandardError; end
    class UnknownService < StandardError; end
    class RateLimitExceeded < StandardError; end
    class ParseError < StandardError; end
  end

  
  

end
