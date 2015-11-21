module Net
  USER_AGENT = "Net - https://bitbucket.org/hipbyte/flow"

  def self.get(url, *options, &callback)
    options = options.first || {}
    Request.get(url, options, callback)
  end
end