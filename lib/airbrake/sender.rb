require 'airbrake/security'

module Airbrake
  # Sends out the notice to Airbrake
  class Sender

    NOTICES_URI = '/notifier_api/v2/notices/'.freeze
    HTTP_ERRORS = [Timeout::Error,
                   Errno::EINVAL,
                   Errno::ECONNRESET,
                   EOFError,
                   Net::HTTPBadResponse,
                   Net::HTTPHeaderSyntaxError,
                   Net::ProtocolError,
                   Errno::ECONNREFUSED].freeze

    def initialize(options = {})
      [:proxy_host, :proxy_port, :proxy_user, :proxy_pass, :protocol,
        :host, :port, :secure, :http_open_timeout, :http_read_timeout].each do |option|
        instance_variable_set("@#{option}", options[option])
      end
    end

    # Sends the notice data off to Airbrake for processing.
    #
    # @param [String] data The XML notice to be sent off
    def send_to_airbrake(data)
      http = setup_http_connection

      http =
        Net::HTTP::Proxy(proxy_host, proxy_port, proxy_user, proxy_pass).
        new(url.host, url.port)

      http.read_timeout = http_read_timeout
      http.open_timeout = http_open_timeout

      # Handle Security
      http.use_ssl = secure
      if secure
        http.ca_file = Airbrake::Security.ca_bundle_path
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end

      response = begin
                   http.post(url.path, data, HEADERS)
                 rescue *HTTP_ERRORS => e
                   log :error, "Timeout while contacting the Airbrake server."
                   nil
                 end

      case response
      when Net::HTTPSuccess then
        log :info, "Success: #{response.class}", response
      else
        log :error, "Failure: #{response.class}", response
      end

      if response && response.respond_to?(:body)
        error_id = response.body.match(%r{<error-id[^>]*>(.*?)</error-id>})
        error_id[1] if error_id
      end
    rescue => e
      log :error, "[Airbrake::Sender#send_to_airbrake] Cannot send notification. Error: #{e.class} - #{e.message}\nBacktrace:\n#{e.backtrace.join("\n\t")}"
      nil
    end

    private

    attr_reader :proxy_host, :proxy_port, :proxy_user, :proxy_pass, :protocol,
      :host, :port, :secure, :http_open_timeout, :http_read_timeout

    def url
      URI.parse("#{protocol}://#{host}:#{port}").merge(NOTICES_URI)
    end

    def log(level, message, response = nil)
      logger.send level, LOG_PREFIX + message if logger
      Airbrake.report_environment_info
      Airbrake.report_response_body(response.body) if response && response.respond_to?(:body)
    end

    def logger
      Airbrake.logger
    end

    def setup_http_connection
      http =
        Net::HTTP::Proxy(proxy_host, proxy_port, proxy_user, proxy_pass).
        new(url.host, url.port)

      http.read_timeout = http_read_timeout
      http.open_timeout = http_open_timeout

      # Handle Security
      http.use_ssl = secure
      if secure
        http.ca_file     = Airbrake::Security.ca_bundle_path
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end

      http
    rescue => e
      log :error, "[Airbrake::Sender#setup_http_connection] Failure initializing the HTTP connection.\nError: #{e.class} - #{e.message}\nBacktrace:\n#{e.backtrace.join("\n\t")}"
      raise e
    end

  end
end
