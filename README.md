WordpressPingbackPortScanner
============================

Wordpress exposes a so called Pingback API to link to other blogposts.
Using this feature you can scan other hosts on the intra- or internet via this server.
You can also use this feature for some kind of distributed port scanning:
You can scan a single host using multiple Wordpress Blogs exposing this API.
This issue was fixed in Wordpress 3.5.1. Older versions are vulnerable,
if the XML-RPC Interface is active.

Examples
--------
Quick-scan a target via a blog:
```
ruby wppps.rb -t http://www.target.com http://www.myblog.com/
```

Use multiple blogs to scan a single target:
```
ruby wppps.rb -t http://www.target.com http://www.myblog1.com/ http://www.myblog2.com/ http://www.myblog3.com/
```

Scan a free wordpress.com blog (all ports) from the internal network:
```
ruby wppps.rb -a -t http://localhost http://myblog.wordpress.com/
```
