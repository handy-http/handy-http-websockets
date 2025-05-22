module handy_http_websockets.components;

import handy_http_websockets.connection;
import handy_http_primitives.request : ServerHttpRequest;

/**
 * An exception that's thrown if an unexpected situation arises while dealing
 * with a websocket connection.
 */
class WebSocketException : Exception {
    import std.exception : basicExceptionCtors;
    import handy_http_primitives.request;
    mixin basicExceptionCtors;
}

/**
 * A text-based websocket message.
 */
struct WebSocketTextMessage {
    WebSocketConnection conn;
    string payload;
}

/**
 * A binary websocket message.
 */
struct WebSocketBinaryMessage {
    WebSocketConnection conn;
    ubyte[] payload;
}

/**
 * A "close" control websocket message indicating the client is closing the
 * connection.
 */
struct WebSocketCloseMessage {
    WebSocketConnection conn;
    ushort statusCode;
    string message;
}

/**
 * An abstract class that you should extend to define logic for handling
 * websocket messages and events. Create a new class that inherits from this
 * one, and overrides any "on..." methods that you'd like.
 */
abstract class WebSocketMessageHandler {
    /**
     * Called when a new websocket connection is established.
     * Params:
     *   conn = The new connection.
     *   request = The HTTP request that initiated the connection.
     */
    void onConnectionEstablished(WebSocketConnection conn, in ServerHttpRequest request) {}

    /**
     * Called when a text message is received.
     * Params:
     *   msg = The message that was received.
     */
    void onTextMessage(WebSocketTextMessage msg) {}

    /**
     * Called when a binary message is received.
     * Params:
     *   msg = The message that was received.
     */
    void onBinaryMessage(WebSocketBinaryMessage msg) {}

    /**
     * Called when a CLOSE message is received. Note that this is called before
     * the socket is necessarily guaranteed to be closed.
     * Params:
     *   msg = The close message.
     */
    void onCloseMessage(WebSocketCloseMessage msg) {}

    /**
     * Called when a websocket connection is closed.
     * Params:
     *   conn = The connection that was closed.
     */
    void onConnectionClosed(WebSocketConnection conn) {}
}
