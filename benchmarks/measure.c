/* measure: run a program and report its wall time, CPU time and peak memory with microsecond precision.
 *   measure OUTFILE PROGRAM [ARGS...]
 * The program's standard output goes to OUTFILE. One line goes to standard error:
 *   wall_seconds user_seconds system_seconds peak_memory_bytes exit_status
 * Used by benchmarks/run.sh; it needs only a C compiler, which every Tomato installation already has. */
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>

static double seconds(struct timeval t) { return (double)t.tv_sec + (double)t.tv_usec / 1e6; }

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: measure OUTFILE PROGRAM [ARGS...]\n"); return 2; }
    struct timeval start, end;
    gettimeofday(&start, NULL);
    pid_t pid = fork();
    if (pid < 0) { perror("measure: fork"); return 2; }
    if (pid == 0) {
        int fd = open(argv[1], O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0) _exit(126);
        if (dup2(fd, 1) < 0) _exit(126);
        close(fd);
        execv(argv[2], argv + 2);
        _exit(127);
    }
    int status = 0;
    struct rusage usage;
    if (wait4(pid, &status, 0, &usage) < 0) { perror("measure: wait4"); return 2; }
    gettimeofday(&end, NULL);
    double maxrss = (double)usage.ru_maxrss;
#ifndef __APPLE__
    maxrss *= 1024;   /* Linux reports kilobytes, macOS bytes */
#endif
    int code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
    fprintf(stderr, "%.6f %.6f %.6f %.0f %d\n", seconds(end) - seconds(start), seconds(usage.ru_utime),
            seconds(usage.ru_stime), maxrss, code);
    return 0;
}
