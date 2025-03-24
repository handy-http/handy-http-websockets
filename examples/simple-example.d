#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-http-transport" version="~>1.1"
    dependency "handy-http-websockets" path="../"
+/

module examples.simple_example;

import handy_http_transport;
import handy_http_primitives;
import handy_http_websockets;
import slf4d;
import core.thread;

class MyMessageHandler : WebSocketMessageHandler {
    private bool closed = false;

    override void onConnectionEstablished(WebSocketConnection conn) {
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
    HttpRequestHandler handler = new WebSocketRequestHandler(new MyMessageHandler());
    new Http1Transport(handler).start();
}
