#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import socket, time, os

START_TIME = time.time()

class EstadoHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        uptime = int(time.time() - START_TIME)
        load1, load5, load15 = os.getloadavg()
        body = (
            f"<html><head><title>Estado del Servidor</title></head><body>"
            f"<h1>Servidor: {socket.gethostname()}</h1>"
            f"<p>Estado: <strong>OK</strong></p>"
            f"<p>Uptime servicio: {uptime}s</p>"
            f"<p>Carga promedio: {load1:.2f}, {load5:.2f}, {load15:.2f}</p>"
            f"</body></html>"
        ).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass

if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8082), EstadoHandler).serve_forever()
