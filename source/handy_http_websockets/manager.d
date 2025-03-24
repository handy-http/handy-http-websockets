module handy_http_websockets.manager;

import core.thread.osthread : Thread;
import core.sync.rwmutex : ReadWriteMutex;
import std.uuid;
import streams;
import slf4d;
import photon : go;

import handy_http_websockets.connection;
import handy_http_websockets.components;
import handy_http_websockets.frame;

__gshared WebSocketManager webSocketManager;

static this() {
    webSocketManager = new WebSocketManager();
}

class WebSocketManager {
    private WebSocketConnection[UUID] connections;
    private ReadWriteMutex connectionsMutex;

    this() {
        connectionsMutex = new ReadWriteMutex();
    }

    void addConnection(WebSocketConnection conn) {
        synchronized(connectionsMutex.writer) {
            connections[conn.id] = conn;
        }
        go(() => connectionHandler(conn));
        conn.getMessageHandler().onConnectionEstablished(conn);
    }

    void removeConnection(WebSocketConnection conn) {
        synchronized(connectionsMutex.writer) {
            connections.remove(conn.id);
        }
        conn.close();
    }

    void broadcast(string text) {
        synchronized(connectionsMutex.reader) {
            foreach (id, conn; connections) {
                try {
                    conn.sendTextMessage(text);
                } catch (WebSocketException e) {
                    warnF!"Failed to broadcast to client %s."(id.toString());
                }
            }
        }
    }
}

void connectionHandler(WebSocketConnection conn) {
    infoF!"Started routine to monitor websocket connection %s."(conn.id.toString());
    bool running = true;
    while (running) {
        try {
            WebSocketFrame f = receiveWebSocketFrame(conn.inputStream);
            switch (f.opcode) {
                case WebSocketFrameOpcode.CONNECTION_CLOSE:
                    webSocketManager.removeConnection(conn);
                    running = false;
                    break;
                case WebSocketFrameOpcode.PING:
                    sendWebSocketPongFrame(conn.outputStream, f.payload);
                    break;
                case WebSocketFrameOpcode.TEXT_FRAME:
                case WebSocketFrameOpcode.BINARY_FRAME:
                    handleClientDataFrame(conn, f);
                    break;
                case WebSocketFrameOpcode.CONTINUATION:
                    warn("Got websocket CONTINUATION frame when not expecting one. Ignoring.");
                    break;
                default:
                    break;
            }
        } catch (Exception e) {
            error(e);
            running = false;
        }
    }
    infoF!"Routine to monitor websocket connection %s has ended."(conn.id.toString());
}

void handleClientDataFrame(WebSocketConnection conn, WebSocketFrame f) {
    bool isText = f.opcode == WebSocketFrameOpcode.TEXT_FRAME;
    ubyte[] payload = f.payload.dup;
    while (!f.finalFragment) {
        f = receiveWebSocketFrame(conn.inputStream);
        if (f.opcode != WebSocketFrameOpcode.CONTINUATION) {
            webSocketManager.removeConnection(conn);
            warnF!"Received invalid websocket frame opcode %s when expecting a CONTINUATION frame."(
                f.opcode
            );
            return;
        }
        payload ~= f.payload;
    }
    if (isText) {
        conn.getMessageHandler().onTextMessage(WebSocketTextMessage(conn, cast(string) payload));
    } else {
        conn.getMessageHandler().onBinaryMessage(WebSocketBinaryMessage(conn, payload));
    }
}
