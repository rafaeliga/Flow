module Net
  class Request
    extend Actions
    include Request::Stubbable

    attr_reader :configuration, :session, :base_url

    def initialize(url, options = {}, session = nil)
      @base_url = url
      @url = Java::Net::URL.new(url)
      @options = options
      @session = session
      @configuration = {}
      
      set_defaults
      configure
    end

    def run(&callback)
      return if stub!(&callback)

      Task.background do
        configuration[:headers].each do |key, value|
          url_connection.setRequestProperty(key, value)
        end
        
        if [:post, :put, :patch, :delete].include?(configuration[:method]) && configuration[:body]
          if configuration[:photo]
            boundary = Java::Lang::Long.toHexString(Java::Lang::System.currentTimeMillis())
            url_connection.setRequestProperty("Content-Type", "multipart/form-data; boundary=" + boundary)
            
            charset = "UTF-8";
            binaryFile = configuration[:photo][:file]
            crlf = "\r\n"
            
            output = url_connection.getOutputStream
            writer = Java::Io::PrintWriter.new(Java::Io::OutputStreamWriter.new(output, charset), true)
            
            # Attaching the params
            model_name = configuration[:body].keys.first
            
            configuration[:body][model_name].map do |k, v|
              param_name = "#{model_name}[#{k}]"
              
              writer.append("--" + boundary).append(crlf)
              writer.append("Content-Disposition: form-data; name=\"#{param_name}\"").append(crlf)
              writer.append("Content-Type: text/plain; charset=" + charset).append(crlf)
              writer.append(crlf).append(v).append(crlf).flush()
            end
            
            # Attaching the file
            writer.append("--" + boundary).append(crlf)
            writer.append("Content-Disposition: form-data; name=\"#{configuration[:photo][:name]}\"; filename=\"" + binaryFile.getName() + "\"").append(crlf)
            writer.append("Content-Type: " + Java::Net::URLConnection.guessContentTypeFromName(binaryFile.getName())).append(crlf)
            writer.append("Content-Transfer-Encoding: binary").append(crlf)
            writer.append(crlf).flush()
            Org::Apache::Commons::Io::FileUtils.copyFile(binaryFile, output)
            output.flush()
            writer.append(crlf).flush()
            
            # End of multipart/form-data
            writer.append("--" + boundary + "--").append(crlf).flush()            
          else
            stream = url_connection.getOutputStream
            body = json? ? configuration[:body].to_json : configuration[:body]
            stream.write(Java::Lang::String.new(body).getBytes("UTF-8"))
          end
          
        end

        response_code = url_connection.getResponseCode
        
        if response_code >= 400
          input_reader = Java::Io::InputStreamReader.new(url_connection.getErrorStream)
        else
          input_reader = Java::Io::InputStreamReader.new(url_connection.getInputStream)
        end
        
  		  input = Java::Io::BufferedReader.new(input_reader)
  		  inputLine = ""
  		  response = Java::Lang::StringBuffer.new
  		  while (inputLine = input.readLine) != nil do
          response.append(inputLine)
        end
        input.close

        Task.main do
          callback.call(ResponseProxy.build_response(url_connection, response))
        end
      end
    end

    private

    def json?
      configuration[:headers].fetch('Content-Type', nil) == "application/json"
    end

    def url_connection
      @url_connection ||= build_url_connection
    end

    def build_url_connection
      connection = @url.openConnection
      connection.setRequestMethod(configuration[:method].to_s.upcase)
      connection.setDoOutput(true) if [:post, :put, :patch, :delete].include?(configuration[:method])
      connection
    end

    def set_defaults
      configuration[:headers] = {
        'User-Agent' => Config.user_agent,
        'Content-Type' => 'application/x-www-form-urlencoded'
      }
      configuration[:method] = :get
      configuration[:body] = ""
      configuration[:connect_timeout] = Config.connect_timeout
      configuration[:read_timeout] = Config.read_timeout
    end

    def configure
      if session
        configuration[:headers].merge!(session.headers)
        if session.authorization
          configuration[:headers].merge!({'Authorization' => session.authorization.to_s})
        end
      end

      configuration.merge!(@options)
    end
  end
end
