module handy_http_websockets.manager;

import core.thread.osthread : Thread;
import core.sync.rwmutex : ReadWriteMutex;
import std.uuid;
import streams;
import slf4d;
import photon : go;
import handy_http_primitives.request : ServerHttpRequest;

import handy_http_websockets.connection;
import handy_http_websockets.components;
import handy_http_websockets.frame;

/** 
 * Global singleton websocket manager that handles all websocket connections.
 * Generally, the `addConnection` method will be called by a `WebSocketRequestHandler`
 * that you've registered in your server, so users will most often use the
 * manager to access the set of connected clients, and broadcast messages to
 * them.
 */
__gshared WebSocketManager webSocketManager;

static this() {
    webSocketManager = new WebSocketManager();
}

/**
 * The websocket manager is responsible for managing all websocket connections.
 */
class WebSocketManager {
    private WebSocketConnection[UUID] connections;
    private ReadWriteMutex connectionsMutex;

    this() {
        connectionsMutex = new ReadWriteMutex();
    }

    /** 
     * Adds a connection to the manager and starts listening for messages.
     * Usually only called by a `WebSocketRequestHandler`.
     * Params:
     *   conn = The connection to add.
     *   request = The HTTP request that initiated the connection.
     */
    void addConnection(WebSocketConnection conn, in ServerHttpRequest request) {
        synchronized(connectionsMutex.writer) {
            connections[conn.id] = conn;
        }
        go(() => connectionHandler(conn));
        conn.getMessageHandler().onConnectionEstablished(conn, request);
        debugF!"Added websocket connection: %s"(conn.id.toString());
    }

    /**
     * Removes a websocket connection from the manager and closes it. This is
     * called automatically if the client sends a CLOSE frame, but you can also
     * call it yourself.
     * Params:
     *   conn = 
     */
    void removeConnection(WebSocketConnection conn) {
        synchronized(connectionsMutex.writer) {
            connections.remove(conn.id);
        }
        conn.close();
        debugF!"Removed websocket connection: %s"(conn.id.toString());
    }

    /**
     * Broadcasts a message to all connected clients.
     * Params:
     *   text = The text to send to all clients.
     */
    void broadcast(string text) {
        debugF!"Broadcasting %d-length text message to all clients."(text.length);
        synchronized(connectionsMutex.reader) {
            foreach (id, conn; connections) {
                try {
                    conn.sendTextMessage(text);
                } catch (WebSocketException e) {
                    warnF!"Failed to broadcast to client %s: %s"(id.toString(), e.msg);
                }
            }
        }
    }

    /**
     * Broadcasts a binary message to all connected clients.
     * Params:
     *   data = The binary data to send to all clients.
     */
    void broadcast(ubyte[] data) {
        debugF!"Broadcasting %d bytes of binary data to all clients."(data.length);
        synchronized(connectionsMutex.reader) {
            foreach (id, conn; connections) {
                try {
                    conn.sendBinaryMessage(data);
                } catch (WebSocketException e) {
                    warnF!"Failed to broadcast to client %s: %s"(id.toString(), e.msg);
                }
            }
        }
    }
}

/**
 * Internal routine that runs in a fiber, and handles an individual websocket
 * connection by listening for messages.
 * Params:
 *   conn = The connection to handle.
 */
private void connectionHandler(WebSocketConnection conn) {
    traceF!"Started routine to monitor websocket connection %s."(conn.id.toString());
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
    traceF!"Routine to monitor websocket connection %s has ended."(conn.id.toString());
}

/** 
 * Handles a websocket data frame (text or binary).
 * Params:
 *   conn = The connection from which the frame was received.
 *   f = The frame that was received.
 */
private void handleClientDataFrame(WebSocketConnection conn, WebSocketFrame f) {
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
