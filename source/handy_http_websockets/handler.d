module handy_http_websockets.handler;

import handy_http_primitives;
import slf4d;
import streams;

import handy_http_websockets.components;
import handy_http_websockets.connection;
import handy_http_websockets.manager : webSocketManager;

/**
 * An HTTP request handler implementation that's used as the entrypoint for
 * clients that want to establish a websocket connection. It will verify the
 * websocket request, and if successful, send back a SWITCHING_PROTOCOLS
 * response, and register a new websocket connection.
 */
class WebSocketRequestHandler : HttpRequestHandler {
    private WebSocketMessageHandler messageHandler;

    /** 
     * Constructs a request handler that will use the given message handler to
     * deal with events from any websocket connections that are established.
     * Params:
     *   messageHandler = The message handler to use.
     */
    this(WebSocketMessageHandler messageHandler) {
        this.messageHandler = messageHandler;
    }

    /** 
     * Handles an incoming HTTP request and tries to establish a websocket
     * connection by first verifying the request, then sending a switching-
     * protocols response, and finally registering the new connection with the
     * websocket manager.
     * Params:
     *   request = The request to read from.
     *   response = The response to write to.
     */
    void handle(ref ServerHttpRequest request, ref ServerHttpResponse response) {
        auto verification = verifyWebSocketRequest(request);
        if (verification == RequestVerificationResponse.INVALID_HTTP_METHOD) {
            sendErrorResponse(response, HttpStatus.METHOD_NOT_ALLOWED, "Only GET requests are allowed.");
            return;
        }
        if (verification == RequestVerificationResponse.MISSING_KEY) {
            sendErrorResponse(response, HttpStatus.BAD_REQUEST, "Missing Sec-WebSocket-Key header.");
            return;
        }
        sendSwitchingProtocolsResponse(request, response);
        webSocketManager.addConnection(new WebSocketConnection(
            messageHandler,
            request.inputStream,
            response.outputStream
        ), request);
    }
}

private enum RequestVerificationResponse {
    INVALID_HTTP_METHOD,
    MISSING_KEY,
    VALID
}

private RequestVerificationResponse verifyWebSocketRequest(in ServerHttpRequest r) {
    if (r.method != HttpMethod.GET) {
        return RequestVerificationResponse.INVALID_HTTP_METHOD;
    }
    if ("Sec-WebSocket-Key" !in r.headers || r.headers["Sec-WebSocket-Key"].length == 0) {
        return RequestVerificationResponse.MISSING_KEY;
    }
    return RequestVerificationResponse.VALID;
}

private void sendErrorResponse(ref ServerHttpResponse response, HttpStatus status, string msg) {
    response.status = status;
    ubyte[] data = cast(ubyte[]) msg;
    import std.conv : to;
    response.headers.add("Content-Type", "text/plain");
    response.headers.add("Content-Length", data.length.to!string);
    auto result = response.outputStream.writeToStream(data);
    if (result.hasError) {
        StreamError e = result.error;
        warnF!"Failed to send HTTP error response: %s"(e.message);
    }
}

private void sendSwitchingProtocolsResponse(in ServerHttpRequest request, ref ServerHttpResponse response) {
    string key = request.headers["Sec-WebSocket-Key"][0];
    response.status = HttpStatus.SWITCHING_PROTOCOLS;
    response.headers.add("Upgrade", "websocket");
    response.headers.add("Connection", "Upgrade");
    response.headers.add("Sec-WebSocket-Accept", generateWebSocketAcceptHeader(key));
    response.outputStream.writeToStream([]); // Trigger this to flush the response.
}

private string generateWebSocketAcceptHeader(string key) {
    import std.digest.sha : sha1Of;
    import std.base64;
    ubyte[20] hash = sha1Of(key ~ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    return Base64.encode(hash);
}

unittest {
    string result = generateWebSocketAcceptHeader("dGhlIHNhbXBsZSBub25jZQ==");
    assert(result == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=");
}
