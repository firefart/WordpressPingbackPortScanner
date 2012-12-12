WordpressPingbackPortScanner
============================

Wordpress exposes a so called Pingback API to link to other blogposts.
Using this feature you can scan other hosts on the intra- or internet via this server.
You can also use this feature for some kind of distributed port scanning:
You can scan a single host using multiple Wordpress Blogs exposing this API.

Examples:
Quick-scan a target via a blog:
```
ruby wppps.rb -t http://www.target.com http://www.myblog.com/xmlrpc.php
```

Use multiple blogs to scan a single target:
```
ruby wppps.rb -t http://www.target.com http://www.myblog1.com/xmlrpc.php http://www.myblog2.com/xmlrpc.php http://www.myblog3.com/xmlrpc.php
```

Scan a free wordpress.com blog (all ports) from the internal network:
```
ruby wppps.rb -a -t http://localhost http://myblog.wordpress.com/xmlrpc.php
```
