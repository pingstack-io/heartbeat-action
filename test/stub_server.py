"""A stand-in for Pingstack's ping endpoint, for the action's tests.

Answers each request with the next status from --statuses (the last one
repeats) and appends "METHOD path?query<TAB>body" to --log.
"""
import argparse
import http.server

parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, required=True)
parser.add_argument("--log", required=True)
parser.add_argument("--statuses", default="200")
args = parser.parse_args()
statuses = [int(code) for code in args.statuses.split(",")]


class Handler(http.server.BaseHTTPRequestHandler):
    def handle_any(self):
        if self.path == "/__ready":
            self.send_response(204)
            self.end_headers()
            return
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode("utf-8") if length else ""
        with open(args.log, "a", encoding="utf-8") as log:
            log.write(f"{self.command} {self.path}\t{body}\n")
        self.send_response(statuses.pop(0) if len(statuses) > 1 else statuses[0])
        self.send_header("Content-Length", "0")
        self.end_headers()

    do_GET = do_POST = handle_any

    def log_message(self, *_):
        pass


http.server.HTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
