#!/usr/bin/env python3
"""
Simple WebSocket server for OpenClaw Fleet Monitor.
Provides real-time updates when fleet data changes.
"""

import asyncio
import websockets
import json
import time
import os
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

DATA_FILE = "data/fleet.json"
WS_PORT = 18789

class FleetDataWatcher(FileSystemEventHandler):
    def __init__(self, websocket_server):
        self.server = websocket_server
    
    def on_modified(self, event):
        if event.src_path.endswith(DATA_FILE):
            print(f"📁 Fleet data updated: {event.src_path}")
            # Notify all connected clients
            asyncio.run_coroutine_threadsafe(
                self.server.broadcast_update(),
                self.server.loop
            )

class WebSocketServer:
    def __init__(self):
        self.clients = set()
        self.loop = None
        self.observer = None
    
    async def register(self, websocket):
        self.clients.add(websocket)
        print(f"🔌 New WebSocket connection. Total clients: {len(self.clients)}")
        
        # Send current data to new client
        try:
            data = self.load_fleet_data()
            await websocket.send(json.dumps({
                "type": "init",
                "data": data,
                "timestamp": time.time()
            }))
        except Exception as e:
            print(f"Error sending initial data: {e}")
    
    async def unregister(self, websocket):
        self.clients.remove(websocket)
        print(f"🔌 WebSocket disconnected. Remaining clients: {len(self.clients)}")
    
    async def handler(self, websocket, path):
        await self.register(websocket)
        try:
            async for message in websocket:
                # Handle incoming messages
                try:
                    data = json.loads(message)
                    await self.handle_message(websocket, data)
                except json.JSONDecodeError:
                    print(f"Invalid JSON received: {message}")
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            await self.unregister(websocket)
    
    async def handle_message(self, websocket, data):
        """Handle incoming WebSocket messages"""
        msg_type = data.get("type", "")
        
        if msg_type == "ping":
            # Respond to ping
            await websocket.send(json.dumps({
                "type": "pong",
                "timestamp": time.time()
            }))
        elif msg_type == "request_update":
            # Send current data
            fleet_data = self.load_fleet_data()
            await websocket.send(json.dumps({
                "type": "update",
                "data": fleet_data,
                "timestamp": time.time()
            }))
        else:
            print(f"Unknown message type: {msg_type}")
    
    def load_fleet_data(self):
        """Load fleet data from JSON file"""
        try:
            with open(DATA_FILE, 'r') as f:
                return json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            return []
    
    async def broadcast_update(self):
        """Broadcast update to all connected clients"""
        if not self.clients:
            return
        
        data = self.load_fleet_data()
        message = json.dumps({
            "type": "update",
            "data": data,
            "timestamp": time.time()
        })
        
        # Send to all clients
        tasks = [client.send(message) for client in self.clients]
        await asyncio.gather(*tasks, return_exceptions=True)
        print(f"📤 Broadcast update to {len(self.clients)} clients")
    
    def start_file_watcher(self):
        """Start watching for file changes"""
        event_handler = FleetDataWatcher(self)
        self.observer = Observer()
        self.observer.schedule(event_handler, os.path.dirname(DATA_FILE), recursive=False)
        self.observer.start()
        print(f"👁️  Watching for changes to {DATA_FILE}")
    
    def stop_file_watcher(self):
        """Stop file watcher"""
        if self.observer:
            self.observer.stop()
            self.observer.join()
    
    async def run(self):
        """Run the WebSocket server"""
        self.loop = asyncio.get_running_loop()
        
        # Start file watcher
        self.start_file_watcher()
        
        # Start WebSocket server
        print(f"🚀 Starting WebSocket server on port {WS_PORT}")
        async with websockets.serve(self.handler, "127.0.0.1", WS_PORT):
            print(f"✅ WebSocket server ready at ws://127.0.0.1:{WS_PORT}")
            await asyncio.Future()  # Run forever
    
    def cleanup(self):
        """Cleanup resources"""
        self.stop_file_watcher()
        print("🛑 WebSocket server cleanup complete")

async def main():
    server = WebSocketServer()
    try:
        await server.run()
    except KeyboardInterrupt:
        print("\n🛑 WebSocket server stopped by user")
    finally:
        server.cleanup()

if __name__ == "__main__":
    # Check if websockets module is installed
    try:
        import websockets
    except ImportError:
        print("❌ websockets module not installed. Install with: pip install websockets")
        print("⚠️  WebSocket server will not start. Polling will still work.")
        exit(1)
    
    # Check if watchdog module is installed
    try:
        from watchdog.observers import Observer
    except ImportError:
        print("❌ watchdog module not installed. Install with: pip install watchdog")
        print("⚠️  File watching disabled. Manual refresh only.")
    
    # Run the server
    asyncio.run(main())