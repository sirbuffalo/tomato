/* The raw-mode slots of the runtime's terminal block (tomato_tty_raw, tomato_tty_restore): a descriptor that is closed by other means
 * leaves its slot active, and a reused descriptor number must neither be taken for the raw terminal it was nor be put back with its
 * old settings. */
#define _GNU_SOURCE
#include "../runtime/tomato_rt.c"
#include <assert.h>
#include <stdlib.h>
const int32_t tomato_kinds[] = {0};
const int32_t *const tomato_offsets[] = {0};
int64_t tomato_parents[] = {0};

static int masters[3];   /* opened first, so that the descriptor numbers freed later are taken by the slaves */
static int open_pty(int i) {   /* the slave side of pseudo-terminal i (its master stays open and keeps the slave alive) */
    int m = masters[i];
    int s = open(ptsname(m), O_RDWR | O_NOCTTY);
    assert(s >= 0);
    return s;
}
static int canonical(int fd) { struct termios t; assert(tcgetattr(fd, &t) == 0); return (t.c_lflag & ICANON) != 0; }

int main(void) {
    for (int i = 0; i < 3; i++) { masters[i] = posix_openpt(O_RDWR | O_NOCTTY); assert(masters[i] >= 0 && grantpt(masters[i]) == 0 && unlockpt(masters[i]) == 0); }
    int a = open_pty(0);
    assert(canonical(a) && tomato_tty_raw(a) == 0 && !canonical(a));
    assert(tomato_tty_raw(a) == 0);                       /* again: nothing changes */
    close(a);                                             /* by other means: the slot stays active */
    int b = open_pty(1);
    assert(b == a);                                       /* the lowest free number is reused */
    assert(canonical(b));
    assert(tomato_tty_raw(b) == 0);
    assert(!canonical(b));                                /* b was made raw, not taken for a */
    assert(tomato_tty_restore(b) == 0);
    assert(canonical(b));                                 /* and gets its own settings back */
    /* a stale slot is not put back onto another terminal at the end */
    int c = open_pty(1);
    assert(tomato_tty_raw(c) == 0);
    close(c);
    int d = open_pty(2);
    assert(d == c && canonical(d));
    struct termios before; assert(tcgetattr(d, &before) == 0);
    tty_restore_signal();                                 /* what a signal handler runs */
    tty_restore_all();
    assert(canonical(d));
    printf("ok\n");
    return 0;
}
