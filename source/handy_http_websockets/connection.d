module handy_http_websockets.connection;

import streams;
import slf4d;
import std.uuid;
import std.socket;

import handy_http_websockets.components;
import handy_http_websockets.frame;

/**
 * All the data that represents a WebSocket connection tracked by the
 * `WebSocketHandler`.
 */
class WebSocketConnection {
    /**
     * The internal id assigned to this connection.
     */
    immutable UUID id;

    /// Stream for reading from the client.
    InputStream!ubyte inputStream;

    /// Stream for writing to the client.
    OutputStream!ubyte outputStream;

    /**
     * The message handler that is called to handle this connection's events.
     */
    private WebSocketMessageHandler messageHandler;

    this(WebSocketMessageHandler messageHandler, InputStream!ubyte inputStream, OutputStream!ubyte outputStream) {
        this.messageHandler = messageHandler;
        this.inputStream = inputStream;
        this.outputStream = outputStream;
        this.id = randomUUID();
    }

    WebSocketMessageHandler getMessageHandler() {
        return this.messageHandler;
    }

    /**
     * Sends a text message to the connected client.
     * Params:
     *   text = The text to send. Should be valid UTF-8.
     */
    void sendTextMessage(string text) {
        sendWebSocketTextFrame(outputStream, text);
    }

    /**
     * Sends a binary message to the connected client.
     * Params:
     *   bytes = The binary data to send.
     */
    void sendBinaryMessage(ubyte[] bytes) {
        sendWebSocketBinaryFrame(outputStream, bytes);
    }

    /**
     * Sends a close message to the client, indicating that we'll be closing
     * the connection.
     * Params:
     *   status = The status code for closing.
     *   message = A message explaining why we're closing. Length must be <= 123.
     */
    void sendCloseMessage(WebSocketCloseStatusCode status, string message) {
        sendWebSocketCloseFrame(outputStream, status, message);
    }

    /**
     * Closes this connection, if it's alive, sending a websocket close message.
     */
    void close() {
        try {
            this.sendCloseMessage(WebSocketCloseStatusCode.NORMAL, null);
        } catch (WebSocketException e) {
            warn("Failed to send a CLOSE message when closing connection " ~ this.id.toString(), e);
        }
        if (auto s = cast(ClosableStream) inputStream) {
            s.closeStream();
        }
        if (auto s = cast(ClosableStream) outputStream) {
            s.closeStream();
        }
        this.messageHandler.onConnectionClosed(this);
    }
}