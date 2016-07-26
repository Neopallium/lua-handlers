var http = require('http');
http.createServer(function (req, res) {
	var body = 'Hello,world!\n';
  res.writeHead(200, {
		'Content-Type': 'text/plain',
		'Content-Length': body.length,
	});
  res.end(body);
}).listen(1080, '0.0.0.0', 8192);
console.log('Server running at http://0.0.0.0:1080/');
