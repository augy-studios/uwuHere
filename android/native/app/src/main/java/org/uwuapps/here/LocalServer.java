/*
 * The smallest web server the hotspot needs (Hotspot.java): plain HTTP/1.1 on the hotspot's own
 * address, for phones joined to it, which have no internet and so nothing else to talk to.
 *
 *   GET  any path   the check-in page
 *   POST /checkin   a check-in, as JSON; answered with the host page's answer, as JSON
 *
 * One request per connection, then closed. Requests are capped (8 KB of headers, 4 KB of body,
 * 10 seconds to send them), and at most 8 are answered at once; the rest wait their turn. No
 * Android classes, so it runs on a desktop JVM too.
 */
package org.uwuapps.here;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketException;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class LocalServer {
    interface Handler {
        /** The answer to a POST /checkin with this body. Called on a worker thread; may block. */
        Answer checkIn(String body);
    }

    static final class Answer {
        final int status;
        final String json;

        Answer(int status, String json) {
            this.status = status;
            this.json = json;
        }
    }

    static final int FIRST_PORT = 8080;
    private static final int PORTS_TO_TRY = 10;
    private static final int MAX_HEADERS = 8 * 1024;
    private static final int MAX_BODY = 4 * 1024;
    private static final int READ_TIMEOUT_MS = 10_000;

    private final ServerSocket socket;
    private final ExecutorService workers = Executors.newFixedThreadPool(8);
    private final byte[] page;
    private final Handler handler;
    private volatile boolean open = true;

    /** Listening on `address`, on the first free port from 8080. */
    LocalServer(InetAddress address, String page, Handler handler) throws IOException {
        this.page = page.getBytes(StandardCharsets.UTF_8);
        this.handler = handler;
        ServerSocket bound = null;
        IOException last = null;
        for (int port = FIRST_PORT; port < FIRST_PORT + PORTS_TO_TRY && bound == null; port++) {
            try {
                bound = new ServerSocket(port, 50, address);
            } catch (IOException e) {
                last = e;
            }
        }
        if (bound == null) throw last;
        socket = bound;
        Thread accept = new Thread(this::acceptLoop, "uwuhere-hotspot-server");
        accept.setDaemon(true);
        accept.start();
    }

    int port() {
        return socket.getLocalPort();
    }

    void close() {
        open = false;
        try {
            socket.close();
        } catch (IOException ignored) {
            // Closing anyway.
        }
        workers.shutdownNow();
    }

    private void acceptLoop() {
        while (open) {
            try {
                Socket client = socket.accept();
                workers.execute(() -> serve(client));
            } catch (SocketException e) {
                return; // closed
            } catch (IOException | RuntimeException e) {
                // One bad connection, or the pool shut down: carry on while open.
            }
        }
    }

    private void serve(Socket client) {
        try (Socket s = client) {
            s.setSoTimeout(READ_TIMEOUT_MS);
            InputStream in = s.getInputStream();
            OutputStream out = s.getOutputStream();

            String head = readHead(in);
            if (head == null) {
                respond(out, 400, "text/plain; charset=utf-8", bytes("Bad request"));
                return;
            }
            String[] lines = head.split("\r\n");
            String[] request = lines[0].split(" ");
            if (request.length < 2) {
                respond(out, 400, "text/plain; charset=utf-8", bytes("Bad request"));
                return;
            }
            String method = request[0];
            String path = request[1];
            int query = path.indexOf('?');
            if (query >= 0) path = path.substring(0, query);

            if ("GET".equals(method) || "HEAD".equals(method)) {
                if ("/favicon.ico".equals(path)) {
                    respond(out, 404, "text/plain; charset=utf-8", bytes("Not found"));
                } else {
                    respond(out, 200, "text/html; charset=utf-8", "HEAD".equals(method) ? new byte[0] : page);
                }
                return;
            }

            if ("POST".equals(method) && "/checkin".equals(path)) {
                int length = contentLength(lines);
                if (length < 0 || length > MAX_BODY) {
                    respond(out, 413, "application/json", bytes("{\"ok\":false,\"error\":\"That check-in is too long.\"}"));
                    return;
                }
                String body = new String(readExactly(in, length), StandardCharsets.UTF_8);
                Answer answer = handler.checkIn(body);
                respond(out, answer.status, "application/json", bytes(answer.json));
                return;
            }

            respond(out, 404, "text/plain; charset=utf-8", bytes("Not found"));
        } catch (IOException | RuntimeException e) {
            // The phone went away mid-request: nothing to answer.
        }
    }

    // Everything before the blank line, or null if it's too long or the connection ends first.
    private static String readHead(InputStream in) throws IOException {
        ByteArrayOutputStream head = new ByteArrayOutputStream();
        int matched = 0;
        final byte[] end = {'\r', '\n', '\r', '\n'};
        while (head.size() < MAX_HEADERS) {
            int b = in.read();
            if (b < 0) return null;
            head.write(b);
            matched = b == end[matched] ? matched + 1 : (b == '\r' ? 1 : 0);
            if (matched == 4) return head.toString("ISO-8859-1").trim();
        }
        return null;
    }

    private static int contentLength(String[] lines) {
        for (int i = 1; i < lines.length; i++) {
            int colon = lines[i].indexOf(':');
            if (colon > 0 && "content-length".equals(lines[i].substring(0, colon).trim().toLowerCase(Locale.ROOT))) {
                try {
                    return Integer.parseInt(lines[i].substring(colon + 1).trim());
                } catch (NumberFormatException e) {
                    return -1;
                }
            }
        }
        return 0;
    }

    private static byte[] readExactly(InputStream in, int length) throws IOException {
        byte[] body = new byte[length];
        int read = 0;
        while (read < length) {
            int n = in.read(body, read, length - read);
            if (n < 0) throw new IOException("Body cut short");
            read += n;
        }
        return body;
    }

    private static void respond(OutputStream out, int status, String type, byte[] body) throws IOException {
        String reason = status == 200 ? "OK" : status == 400 ? "Bad Request" : status == 404 ? "Not Found"
                : status == 413 ? "Payload Too Large" : status == 503 ? "Service Unavailable" : "Error";
        String head = "HTTP/1.1 " + status + " " + reason + "\r\n"
                + "Content-Type: " + type + "\r\n"
                + "Content-Length: " + body.length + "\r\n"
                + "Cache-Control: no-store\r\n"
                + "Connection: close\r\n\r\n";
        out.write(head.getBytes(StandardCharsets.ISO_8859_1));
        out.write(body);
        out.flush();
    }

    private static byte[] bytes(String text) {
        return text.getBytes(StandardCharsets.UTF_8);
    }
}
