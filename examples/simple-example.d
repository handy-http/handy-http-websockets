#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-http-transport" version="~>1.1"
    dependency "handy-http-websockets" path="../"
+/

/**
 * This example demonstrates a simple websocket server that broadcasts a
 * message to all connected clients every 5 seconds. It also responds to
 * incoming text messages. See the `simple-example.html` file which is served
 * when you open your browser to http://localhost:8080.
 */
module examples.simple_example;

import handy_http_transport;
import handy_http_primitives;
import handy_http_websockets;
import slf4d;
import core.thread;

class MyMessageHandler : WebSocketMessageHandler {
    private bool closed = false;

    override void onConnectionEstablished(WebSocketConnection conn, in ServerHttpRequest req) {
        info("Connection established.");
        import photon : go;
        go(() {
            while (!closed) {
                info("Broadcasting...");
                webSocketManager.broadcast("BROADCAST TEST!");
                Thread.sleep(seconds(5));
            }
        });
    }

    override void onTextMessage(WebSocketTextMessage msg) {
        infoF!"Got a text message: %s"(msg.payload);
        msg.conn.sendTextMessage("test");
    }

    override void onBinaryMessage(WebSocketBinaryMessage msg) {
        infoF!"Got a binary message: %s"(msg.payload);
    }

    override void onCloseMessage(WebSocketCloseMessage msg) {
        infoF!"Got a close message: %d - %s"(msg.statusCode, msg.message);
    }

    override void onConnectionClosed(WebSocketConnection conn) {
        info("Connection closed.");
        closed = true;
    }
}

void main() {
    // Create a websocket request handler that will accept incoming websocket
    // connections, and use the given message handler to handle any events.
    HttpRequestHandler wsHandler = new WebSocketRequestHandler(new MyMessageHandler());

    // Create the main HTTP request handler that will determine whether to
    // open a websocket connection or serve the HTML file, depending on the
    // request URL.
    HttpRequestHandler handler = HttpRequestHandler.of((ref ServerHttpRequest req, ref ServerHttpResponse resp) {
        if (req.url == "/ws") {
            // Handle websocket requests.
            wsHandler.handle(req, resp);
        } else {
            // Serve the HTML file.
            import std.conv : to;
            import std.file : readText;
            const html = readText("simple-example.html");
            resp.headers.add("Content-Type", "text/html");
            resp.headers.add("Content-Length", html.length.to!string);
            resp.outputStream.writeToStream(cast(ubyte[]) html);
        }
    });

    // Start the server with all default settings.
    new Http1Transport(handler).start();
}
