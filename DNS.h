// DNS.h - tiny UDP DNS client (A records) - AFLATOON
#ifndef AP_DNS_H
#define AP_DNS_H
#include <netinet/in.h>
// returns 1 on success and fills *out, 0 on failure
int ap_dns_resolve(const char *host, const char *server, unsigned short port, struct in_addr *out);
#endif
