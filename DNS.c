// DNS.c - AFLATOON
#include "DNS.h"
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

static unsigned short rand16(void) {
#ifdef __APPLE__
    return (unsigned short)arc4random();
#else
    return (unsigned short)rand();
#endif
}

int ap_dns_resolve(const char *host, const char *server, unsigned short port, struct in_addr *out) {
    unsigned char q[512];
    memset(q, 0, sizeof q);
    unsigned short qid = rand16();
    q[0] = qid >> 8; q[1] = qid & 0xff;
    q[2] = 0x01;            // RD
    q[5] = 1;               // QDCOUNT
    int p = 12;
    const char *s = host;
    while (*s) {
        const char *dot = strchr(s, '.');
        size_t len = dot ? (size_t)(dot - s) : strlen(s);
        if (len == 0 || len > 63 || p + (int)len + 6 > 500) return 0;
        q[p++] = (unsigned char)len;
        memcpy(q + p, s, len); p += (int)len;
        s += len; if (*s == '.') s++;
    }
    q[p++] = 0; q[p++] = 0; q[p++] = 1; q[p++] = 0; q[p++] = 1;   // root, QTYPE=A, QCLASS=IN

    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return 0;
    struct timeval tv = {2, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    struct sockaddr_in sa;
    memset(&sa, 0, sizeof sa);
    sa.sin_family = AF_INET;
    sa.sin_port = htons(port);
    if (inet_pton(AF_INET, server, &sa.sin_addr) != 1) { close(fd); return 0; }
    if (sendto(fd, q, (size_t)p, 0, (struct sockaddr *)&sa, sizeof sa) < 0) { close(fd); return 0; }

    unsigned char r[512];
    ssize_t n = recv(fd, r, sizeof r, 0);
    close(fd);
    if (n < 12) return 0;
    if (r[0] != q[0] || r[1] != q[1]) return 0;      // id mismatch
    if (!(r[2] & 0x80)) return 0;                    // not a response
    if ((r[3] & 0x0F) != 0) return 0;                // rcode != NOERROR

    int an = (r[6] << 8) | r[7];
    int i = 12;
    while (i < n && r[i]) i += r[i] + 1;             // skip question name
    i += 5;                                          // root byte + QTYPE + QCLASS
    for (int k = 0; k < an && i < n; k++) {
        if ((r[i] & 0xC0) == 0xC0) i += 2;
        else { while (i < n && r[i]) i += r[i] + 1; i++; }
        if (i + 10 > n) return 0;
        int type = (r[i] << 8) | r[i + 1];
        int rdlen = (r[i + 8] << 8) | r[i + 9];
        i += 10;
        if (i + rdlen > n) return 0;
        if (type == 1 && rdlen == 4) { memcpy(out, r + i, 4); return 1; }
        i += rdlen;
    }
    return 0;
}
