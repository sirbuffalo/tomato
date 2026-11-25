/* The descriptor waits of the runtime (fd_wait, fd_step, fd_cancel_frame, tomato_sock_close), once with the kernel set
 * (epoll/kqueue) where there is one and once with it switched off, so the poll path that backs it up is checked too. */
#include "../runtime/tomato_rt.c"
#include <assert.h>
#include <sys/socket.h>
const int32_t tomato_kinds[] = {0};
const int32_t *const tomato_offsets[] = {0};
int64_t tomato_parents[] = {0};

static void lifecycle(void) {
    int p[2]; assert(pipe(p) == 0);
    Hdr a = {-1, 0}, b = {-1, 0}, c = {-1, 0};
    tomato_fd_wait(&a, p[0], 1); tomato_fd_wait(&b, p[0], 1);
    tomato_fd_wait(&c, p[1], 2);
    assert(fd_step() == 1 && tomato_q_pop() == &c);
    assert(fd_step() == 0);
    assert(write(p[1], "x", 1) == 1);
    assert(fd_step() == 2 && tomato_q_pop() == &a && tomato_q_pop() == &b);
    assert(fd_n == 0);
    tomato_fd_wait(&a, p[0], 1); tomato_fd_wait(&b, p[0], 1);
    assert(fd_cancel_frame(&a)); tomato_sock_close(p[0]);
    assert(tomato_q_pop() == &b && fd_n == 0); close(p[1]);

    /* a reader and a writer of one descriptor are woken separately; a hang-up wakes a reader */
    int s[2]; assert(socketpair(AF_UNIX, SOCK_STREAM, 0, s) == 0);
    tomato_fd_wait(&a, s[0], 1); tomato_fd_wait(&b, s[0], 2);
    assert(fd_step() == 1 && tomato_q_pop() == &b);
    assert(fd_step() == 0);
    assert(fd_cancel_frame(&b) == 0);
    close(s[1]); assert(fd_step() == 1 && tomato_q_pop() == &a && fd_n == 0); close(s[0]);

    /* more ready descriptors than one kernel call returns, among idle ones */
    enum { N = 400 }; static int pp[N][2]; static Hdr fr[N];
    for (int i = 0; i < N; i++) { assert(pipe(pp[i]) == 0); tomato_fd_wait(&fr[i], pp[i][0], 1); }
    assert(fd_step() == 0);
    for (int i = 0; i < N; i += 2) assert(write(pp[i][1], "x", 1) == 1);
    int woke = 0; for (int k = 0; k < 4 && woke < N / 2; k++) woke += fd_step();
    assert(woke == N / 2 && fd_n == N / 2);
    for (int i = 0; i < N / 2; i++) assert(tomato_q_pop() != 0);
    for (int i = 1; i < N; i += 2) assert(fd_cancel_frame(&fr[i]));
    for (int i = 0; i < N; i++) { close(pp[i][0]); close(pp[i][1]); }
    assert(fd_n == 0 && tomato_q_pop() == 0);

    /* io_block sleeps while nothing is ready (a spin would return at once) and returns when a descriptor is ready */
    assert(pipe(p) == 0);
    tomato_fd_wait(&a, p[0], 1);
    double t = real_seconds(); io_block(100);
    assert(real_seconds() - t >= 0.05);
    assert(write(p[1], "x", 1) == 1);
    t = real_seconds(); io_block(5000);
    assert(real_seconds() - t < 2);
    assert(fd_step() == 1 && tomato_q_pop() == &a); close(p[0]); close(p[1]);
}

int main(void) {
    lifecycle();
#ifdef FD_KERNEL_SET
    assert(fd_backend >= 0);   /* the kernel set was in use */
    fd_backend_fail();         /* now the poll path alone */
    lifecycle();
    assert(fd_backend == -1);
#endif
    return 0;
}
