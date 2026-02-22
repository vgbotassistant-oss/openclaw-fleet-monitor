#!/usr/bin/env python3
"""
Simple HTTP server for OpenClaw Fleet Monitor dashboard.
Serves dashboard.html and data/fleet.json
"""

import http.server
import socketserver
import os
import json
from pathlib import Path
from datetime import datetime

PORT = 8081
DATA_FILE = "data/fleet.json"

class FleetMonitorHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        # Serve dashboard.html as default
        if self.path == "/" or self.path == "/index.html":
            self.path = "/dashboard.html"
        
        # Serve fleet.json from data directory
        if self.path == "/data/fleet.json":
            self.serve_fleet_json()
            return
        
        # Serve other files normally
        return super().do_GET()
    
    def serve_fleet_json(self):
        """Serve the fleet.json file with proper headers"""
        try:
            filepath = Path(DATA_FILE)
            if not filepath.exists():
                # Return empty array if file doesn't exist
                data = []
                content = json.dumps(data).encode('utf-8')
            else:
                with open(filepath, 'rb') as f:
                    content = f.read()
            
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.send_header("Pragma", "no-cache")
            self.send_header("Expires", "0")
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)
            
        except Exception as e:
            self.send_error(500, f"Error serving fleet.json: {str(e)}")
    
    def log_message(self, format, *args):
        """Custom log format with timestamp"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"{timestamp} - {self.address_string()} - {format % args}")

def main():
    # Change to project directory
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    
    # Create data directory if it doesn't exist
    os.makedirs("data", exist_ok=True)
    
    print(f"🚀 Starting OpenClaw Fleet Monitor server on port {PORT}")
    print(f"📊 Dashboard: http://localhost:{PORT}/")
    print(f"📁 Data endpoint: http://localhost:{PORT}/data/fleet.json")
    print(f"📂 Serving from: {os.getcwd()}")
    print("Press Ctrl+C to stop\n")
    
    try:
        with socketserver.TCPServer(("", PORT), FleetMonitorHandler) as httpd:
            print(f"✅ Server started successfully")
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 Server stopped by user")
    except Exception as e:
        print(f"❌ Server error: {e}")
        return 1
    
    return 0

if __name__ == "__main__":
    exit(main())