/* A tiny HTTP server for the requests tests (tests/run.sh builds it with clang): no internet needed.
 * It listens on 127.0.0.1 on a free port, prints the port on one line of standard output, and serves one request per
 * connection (a child process each, so slow requests overlap). Routes:
 *   /hello            200 "hello", with Content-Type text/plain and a duplicated X-Tag header
 *   /echo             200, the request line, headers (names lower-cased) and body as text, in that order
 *   /status/N         status N with the body "status N"
 *   /redirect/N       N redirects (302) that end at /hello;  /loop redirects to itself
 *   /redirect-post    303 to /echo
 *   /chunked          "alpha-beta-gamma" sent with chunked encoding
 *   /binary           the 256 byte values 0..255
 *   /big              4 MiB of the letter x
 *   /badutf8          the bytes 'a' 0xFF 'b' 0xC3 0x28
 *   /slow/MS          waits MS milliseconds, then answers "slow MS"
 *   /empty            200 with no body
 *   /drop             closes the connection without answering
 *   /quit             stops the server
 */
#include <arpa/inet.h>
#include <ctype.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

static void send_all(int fd, const char *p, size_t n) {
    while (n > 0) { ssize_t k = write(fd, p, n); if (k <= 0) return; p += k; n -= (size_t)k; }
}

static void reply(int fd, int status, const char *extra, const char *body, size_t n) {
    char head[1024];
    int len = snprintf(head, sizeof head, "HTTP/1.1 %d X\r\nContent-Length: %zu\r\nConnection: close\r\n%s\r\n", status, n, extra);
    send_all(fd, head, (size_t)len);
    send_all(fd, body, n);
}

static void handle(int fd) {
    char req[65536]; size_t have = 0; ssize_t k;
    char *end = NULL;
    while (have < sizeof req - 1 && (k = read(fd, req + have, sizeof req - 1 - have)) > 0) {
        have += (size_t)k; req[have] = 0;
        if ((unsigned char)req[0] == 0x16) return;
        if ((end = strstr(req, "\r\n\r\n"))) break;
    }
    if (have > 0 && (unsigned char)req[0] == 0x16) return;      /* a TLS handshake: this server only speaks plain HTTP, so hang up */
    if (!end) return;
    size_t head_len = (size_t)(end - req) + 4;
    long clen = 0;
    for (char *p = req; p < end; p++) if (strncasecmp(p, "\r\ncontent-length:", 17) == 0) clen = atol(p + 17);
    while (have < head_len + (size_t)clen && have < sizeof req - 1 && (k = read(fd, req + have, sizeof req - 1 - have)) > 0) { have += (size_t)k; }
    req[have] = 0;
    char method[16] = "", path[512] = "";
    sscanf(req, "%15s %511s", method, path);
    if (strcmp(path, "/hello") == 0) reply(fd, 200, "Content-Type: text/plain\r\nX-Tag: one\r\nX-Tag: two\r\n", "hello", 5);
    else if (strcmp(path, "/echo") == 0 || strncmp(path, "/echo?", 6) == 0) {
        char out[70000]; size_t o = 0;
        char *line_end = strstr(req, "\r\n");
        o += (size_t)snprintf(out + o, sizeof out - o, "%.*s\n", (int)(line_end - req), req);
        for (char *p = line_end + 2; p < end; ) {
            char *e = strstr(p, "\r\n"); if (!e) break;
            for (char *q = p; q < e && *q != ':'; q++) *q = (char)tolower((unsigned char)*q);
            if (strncmp(p, "user-agent", 10) != 0 && strncmp(p, "accept", 6) != 0 && strncmp(p, "host", 4) != 0)
                o += (size_t)snprintf(out + o, sizeof out - o, "%.*s\n", (int)(e - p), p);
            p = e + 2;
        }
        o += (size_t)snprintf(out + o, sizeof out - o, "--\n%.*s", (int)(have - head_len), req + head_len);
        reply(fd, 200, "Content-Type: text/plain\r\n", out, o);
    } else if (strncmp(path, "/status/", 8) == 0) {
        char b[64]; int n = snprintf(b, sizeof b, "status %s", path + 8);
        reply(fd, atoi(path + 8), "Content-Type: text/plain\r\n", b, (size_t)n);
    } else if (strncmp(path, "/redirect/", 10) == 0) {
        int n = atoi(path + 10); char loc[128];
        if (n <= 0) reply(fd, 302, "Location: /hello\r\n", "", 0);
        else { snprintf(loc, sizeof loc, "Location: /redirect/%d\r\n", n - 1); reply(fd, 302, loc, "", 0); }
    } else if (strcmp(path, "/loop") == 0) reply(fd, 302, "Location: /loop\r\n", "", 0);
    else if (strcmp(path, "/redirect-post") == 0) reply(fd, 303, "Location: /echo\r\n", "", 0);
    else if (strcmp(path, "/chunked") == 0) {
        const char *r = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n6\r\nalpha-\r\n5\r\nbeta-\r\n5\r\ngamma\r\n0\r\n\r\n";
        send_all(fd, r, strlen(r));
    } else if (strcmp(path, "/binary") == 0) {
        char b[256]; for (int i = 0; i < 256; i++) b[i] = (char)i;
        reply(fd, 200, "Content-Type: application/octet-stream\r\n", b, 256);
    } else if (strcmp(path, "/big") == 0) {
        size_t n = 4u << 20; char *b = malloc(n); memset(b, 'x', n); reply(fd, 200, "", b, n);
    } else if (strcmp(path, "/badutf8") == 0) reply(fd, 200, "", "a\xFF" "b\xC3\x28", 5);
    else if (strncmp(path, "/slow/", 6) == 0) {
        int ms = atoi(path + 6); usleep((useconds_t)ms * 1000);
        char b[64]; int n = snprintf(b, sizeof b, "slow %d", ms); reply(fd, 200, "", b, (size_t)n);
    } else if (strcmp(path, "/empty") == 0) reply(fd, 200, "", "", 0);
    else if (strcmp(path, "/drop") == 0) return;
    else if (strcmp(path, "/quit") == 0) { reply(fd, 200, "", "bye", 3); kill(getppid(), SIGTERM); }
    else reply(fd, 404, "", "not found", 9);
}

int main(void) {
    signal(SIGPIPE, SIG_IGN); signal(SIGCHLD, SIG_IGN);
    int s = socket(AF_INET, SOCK_STREAM, 0), one = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a = {0}; a.sin_family = AF_INET; a.sin_addr.s_addr = htonl(INADDR_LOOPBACK); a.sin_port = 0;
    if (bind(s, (struct sockaddr *)&a, sizeof a) != 0 || listen(s, 64) != 0) return 1;
    socklen_t len = sizeof a; getsockname(s, (struct sockaddr *)&a, &len);
    printf("%d\n", ntohs(a.sin_port)); fflush(stdout);
    for (;;) {
        int c = accept(s, NULL, NULL);
        if (c < 0) continue;
        if (fork() == 0) { close(s); handle(c); close(c); _exit(0); }
        close(c);
    }
}
