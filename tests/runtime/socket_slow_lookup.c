/* Link with --wrap=getaddrinfo to make a lookup predictably slow without external DNS. */
#include <netdb.h>
#include <string.h>
#include <unistd.h>
int __real_getaddrinfo(const char *, const char *, const struct addrinfo *, struct addrinfo **);
int __wrap_getaddrinfo(const char *name, const char *service, const struct addrinfo *hints, struct addrinfo **out) {
    if (name && strcmp(name, "slow.test") == 0) {
        usleep(250000);
        name = "127.0.0.1";
    }
    return __real_getaddrinfo(name, service, hints, out);
}
