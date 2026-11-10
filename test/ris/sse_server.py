#!/usr/bin/env python3
"""An event stream on loopback for test/ris/sse_open.ri.

The first connection sends one event and closes; a reconnect must name
it in Last-Event-ID and gets the next. Writes the port to DIR/port, then
DIR/ready.

    python3 test/ris/sse_server.py DIR
"""
import http.server
import os
import sys

seen = []


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def do_GET(self):
        last = self.headers.get("Last-Event-ID", "")
        seen.append(last)
        if last == "":
            body = "retry: 10\nid: 1\ndata: first\n\n"
        elif last == "1":
            body = "event: update\nid: 2\ndata: second\ndata: line\n\n"
        else:
            body = "data: unexpected %s\n\n" % last
        data = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


def main():
    out = sys.argv[1]
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    with open(os.path.join(out, "port"), "w") as f:
        f.write(str(server.server_address[1]))
    open(os.path.join(out, "ready"), "w").close()
    server.serve_forever()


main()
