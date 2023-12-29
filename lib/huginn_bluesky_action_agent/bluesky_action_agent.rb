module Agents
  class BlueskyActionAgent < Agent
    include FormConfigurable
    can_dry_run!
    no_bulk_receive!
    default_schedule 'never'

    description do
      <<-MD
      The Bluesky Action Agent can like or repost feeds from the events it receives.

      `debug` is used for verbose mode.

      `like` if you want to like the feed.

      `repost` if you want to repost the feed.

      `uri` is mandatory to interact with the wanted feed.

      `cid` is mandatory to interact with the wanted feed.

      `handle` is mandatory for authentication.

      `app_password` is mandatory for authentication.

      `expected_receive_period_in_days` is used to determine if the Agent is working. Set it to the maximum number of days
      that you anticipate passing without this Agent receiving an incoming Event.
      MD
    end

    event_description <<-MD
      Events look like this:

          {
            "uri": "at://did:plc:XXXXXXXXXXXXXXXXXXXXXXXX/app.bsky.feed.like/XXXXXXXXXXXXX",
            "cid": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    MD

    def default_options
      {
        'uri' => "{{ post.uri }}",
        'cid' => "{{ post.cid }}",
        'debug' => 'false',
        'repost' => 'false',
        'like' => 'true',
        'handle' => '',
        'app_password' => '',
        'emit_events' => 'true',
        'expected_receive_period_in_days' => '2',
      }
    end

    form_configurable :uri, type: :string
    form_configurable :cid, type: :string
    form_configurable :debug, type: :boolean
    form_configurable :repost, type: :boolean
    form_configurable :like, type: :boolean
    form_configurable :app_password, type: :string
    form_configurable :handle, type: :string
    form_configurable :emit_events, type: :boolean
    form_configurable :expected_receive_period_in_days, type: :string
    def validate_options
      unless options['uri'].present?
        errors.add(:base, "uri is a required field")
      end

      unless options['cid'].present?
        errors.add(:base, "cid is a required field")
      end

      unless options['app_password'].present?
        errors.add(:base, "app_password is a required field")
      end

      if options.has_key?('emit_events') && boolify(options['emit_events']).nil?
        errors.add(:base, "if provided, emit_events must be true or false")
      end

      unless options['handle'].present?
        errors.add(:base, "handle is a required field")
      end

      if options.has_key?('debug') && boolify(options['debug']).nil?
        errors.add(:base, "if provided, debug must be true or false")
      end

      if options.has_key?('repost') && boolify(options['repost']).nil?
        errors.add(:base, "if provided, repost must be true or false")
      end

      if options.has_key?('like') && boolify(options['like']).nil?
        errors.add(:base, "if provided, like must be true or false")
      end

      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end
    end

    def working?
      event_created_within?(options['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          log event
          action()
        end
      end
    end

    def check
      action()
    end

    private

    def log_curl_output(code,body)

      log "request status : #{code}"

      if interpolated['debug'] == 'true'
        log "body"
        log body
      end

    end

    def generate_did()
      uri = URI.parse("https://bsky.social/xrpc/com.atproto.identity.resolveHandle")
      params = { :handle => interpolated['handle'] }
      uri.query = URI.encode_www_form(params)
      response = Net::HTTP.get_response(uri)
    
      log_curl_output(response.code,response.body)
    
      return JSON.parse(response.body)['did']
    end
    
    def generate_api_key(did)
      uri = URI.parse("https://bsky.social/xrpc/com.atproto.server.createSession")
      request = Net::HTTP::Post.new(uri)
      request.content_type = "application/json"
      request.body = JSON.dump({
        "identifier" => did,
        "password" => interpolated['app_password']
      })
    
      req_options = {
        use_ssl: uri.scheme == "https",
      }
    
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end
    
      log_curl_output(response.code,response.body)
    
      return JSON.parse(response.body)['accessJwt']
    end
    
    def repost_feed()

      did = generate_did()    
      uri = URI.parse("https://bsky.social/xrpc/com.atproto.repo.createRecord")
      request = Net::HTTP::Post.new(uri)
      request.content_type = "application/json"
      request["Authorization"] = "Bearer #{generate_api_key(did)}"
      request.body = JSON.dump({
        "collection" => "app.bsky.feed.repost",
        "repo" => did,
        "record" => {
          "subject" => {
            "uri" => interpolated['uri'],
            "cid" => interpolated['cid']
          },
          "createdAt" => Time.now.strftime('%Y-%m-%dT%H:%M:%S.%3NZ'),
          "$type" => "app.bsky.feed.repost"
        }
      })
      
      req_options = {
        use_ssl: uri.scheme == "https",
      }
      
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end
    
      log_curl_output(response.code,response.body)
    
      if interpolated['emit_events'] == 'true'
        create_event payload: response.body
      end

    end
    
    def like_feed()

      did = generate_did()    
      uri = URI.parse("https://bsky.social/xrpc/com.atproto.repo.createRecord")
      request = Net::HTTP::Post.new(uri)
      request.content_type = "application/json"
      request["Authorization"] = "Bearer #{generate_api_key(did)}"
      request.body = JSON.dump({
        "collection" => "app.bsky.feed.like",
        "repo" => did,
        "record" => {
          "subject" => {
            "uri" => interpolated['uri'],
            "cid" => interpolated['cid']
          },
          "createdAt" => Time.now.strftime('%Y-%m-%dT%H:%M:%S.%3NZ'),
          "$type" => "app.bsky.feed.like"
        }
      })
      
      req_options = {
        use_ssl: uri.scheme == "https",
      }
      
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end
    
      log_curl_output(response.code,response.body)
    
      if interpolated['emit_events'] == 'true'
        create_event payload: response.body
      end

    end
    
    def action()

      if interpolated['repost'] == 'true'
        repost_feed()
      end
      if interpolated['like'] == 'true'
        like_feed()
      end
    
    end
  end
end
