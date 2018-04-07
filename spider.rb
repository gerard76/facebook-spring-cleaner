# Remove all your facebook actitity with this simple webcrawler in Ruby
#
# Crawler base from https://rossta.net/blog/how-to-write-a-simple-web-crawler-in-ruby-revisited.html
#
# Requirements:
#   Ruby 2.0+
#
require "mechanize"
require "pry"

class Spider
  REQUEST_INTERVAL = 0.2
  MAX_URLS = 10000

  attr_reader :handlers

  def initialize(processor, options = {})
    @processor = processor
    @options   = options

    @results  = []
    @urls     = []
    @handlers = {}

    @interval = options.fetch(:interval, REQUEST_INTERVAL)
    @max_urls = options.fetch(:max_urls, MAX_URLS)

    enqueue(@processor.root, @processor.handler)
  end

  def enqueue(url, method, data = {})
    return if @handlers[url]
    @urls << url
    @handlers[url] ||= { method: method, data: data }
  end

  def record(data = {})
    @results << data
  end

  def results
    return enum_for(:results) unless block_given?

    i = @results.length
    enqueued_urls.each do |url, handler|
      begin
        log "Calling", url.inspect
        @processor.send(handler[:method], agent.get(url), handler[:data])
        if block_given? && @results.length > i
          yield @results.last
          i += 1
        end
      rescue => ex
        log "Error", "#{url.inspect}, #{ex}"
      end
      sleep @interval if @interval > 0
    end
  end

  private

  def enqueued_urls
    Enumerator.new do |y|
      index = 0
      while index < @urls.count && index <= @max_urls
        url = @urls[index]
        index += 1
        next unless url
        y.yield url, @handlers[url]
      end
    end
  end

  def log(label, info)
    warn "%-10s: %s" % [label, info]
  end

  def agent
    @agent ||= (
      agent = Mechanize.new
      
      if File.exist?("cookies.yaml")
        agent.cookie_jar.load("cookies.yaml")
      else
        log "Logging in", "..."
        login_page = agent.get("https://mbasic.facebook.com/login.php")
        form  = login_page.forms.first
        form.email = @options[:email]
        form.pass  = @options[:pass]
        agent.submit(form)
        
        agent.cookie_jar.save("cookies.yaml", session: true)
      end
      
      agent
    )
  end
end

class ProgrammableWeb
  attr_reader :root, :handler

  def initialize(root, **options)
    @root = root
    @handler = :process_index
    @options = options
  end

  def process_index(page, data = {})
    page.links_with(href: /\/allactivity\?timeend=/).each do |link|
      spider.enqueue(link.href, :process_index)
    end

    page.links_with(href: /\/allactivity\/removecontent/).each do |link|
      spider.enqueue(link.href, :delete)
    end
    
    page.links_with(href: /\/allactivity\/delete/).each do |link|
      spider.enqueue(link.href, :delete)
    end
  end

  def delete(page, data = {})
    spider.record page.uri
  end

  def results(&block)
    spider.results(&block)
  end

  private

  def spider
    @spider ||= Spider.new(self, @options)
  end
end

if __FILE__ == $0
  email = "***"
  pass  = "***"
  fid   = "***"
  spider = ProgrammableWeb.new("https://mbasic.facebook.com/#{fid}/allactivity", email: email, pass: pass)

  # spider.results.lazy.take(5).each_with_index do |result, i|
  spider.results.each_with_index do |result, i|
    warn "%-2s: %s" % [i, result.inspect]
  end
end
