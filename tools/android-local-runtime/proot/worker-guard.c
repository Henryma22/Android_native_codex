/*
 * Small host-side supervisor for the KernelSU-assisted PRoot launcher.
 *
 * The Android app starts this executable as its direct child. The guard
 * starts the fixed su command as its child, forwards all standard file
 * descriptors unchanged, and turns parent death into child termination.
 * This is not a shell, command runner, or root API: argv[1..] is the
 * already-built fixed su invocation supplied by the Kotlin launcher.
 */

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t child_pid = -1;
static volatile sig_atomic_t stop_requested = 0;

static volatile sig_atomic_t supervisor_child_pid = -1;
static volatile sig_atomic_t supervisor_group_id = -1;
static volatile sig_atomic_t supervisor_stop_requested = 0;

static void request_stop(int signal_number) {
    (void)signal_number;
    stop_requested = 1;
    if (child_pid > 1) {
        (void)kill((pid_t)child_pid, SIGTERM);
    }
}

static void request_supervisor_stop(int signal_number) {
    (void)signal_number;
    supervisor_stop_requested = 1;
    if (supervisor_group_id > 1) {
        (void)kill(-(pid_t)supervisor_group_id, SIGTERM);
    } else if (supervisor_child_pid > 1) {
        (void)kill((pid_t)supervisor_child_pid, SIGTERM);
    }
}

static long long monotonic_millis(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return 0;
    return (long long)now.tv_sec * 1000LL + now.tv_nsec / 1000000LL;
}

static void sleep_millis(long millis) {
    struct timespec duration = {
        .tv_sec = millis / 1000,
        .tv_nsec = (millis % 1000) * 1000000L,
    };
    while (nanosleep(&duration, &duration) != 0 && errno == EINTR) {
        /* Parent and child are checked again in the main loop. */
    }
}

static int child_exit_code(int status) {
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return 125;
}

static int parse_positive_number(const char *value, long minimum, long maximum, long *out) {
    if (value == NULL || value[0] == '\0' || out == NULL) return 0;
    char *end = NULL;
    errno = 0;
    const long parsed = strtol(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0') return 0;
    if (parsed < minimum || parsed > maximum) return 0;
    *out = parsed;
    return 1;
}

static int read_process_uid(pid_t pid, uid_t *uid_out) {
    if (pid <= 1 || uid_out == NULL) return 0;

    char path[64];
    const int length = snprintf(path, sizeof(path), "/proc/%ld/status", (long)pid);
    if (length <= 0 || (size_t)length >= sizeof(path)) return 0;

    const int descriptor = open(path, O_RDONLY | O_CLOEXEC);
    if (descriptor < 0) return 0;
    char contents[2048];
    const ssize_t count = read(descriptor, contents, sizeof(contents) - 1);
    (void)close(descriptor);
    if (count <= 0) return 0;
    contents[count] = '\0';

    const char *uid_line = strstr(contents, "Uid:");
    if (uid_line == NULL) return 0;
    unsigned long real_uid = 0;
    if (sscanf(uid_line, "Uid: %lu", &real_uid) != 1) return 0;
    *uid_out = (uid_t)real_uid;
    return 1;
}

static int process_is_alive_for_uid(pid_t pid, uid_t expected_uid) {
    if (pid <= 1) return 0;
    if (kill(pid, 0) != 0 && errno != EPERM) return 0;
    uid_t actual_uid = (uid_t)-1;
    if (!read_process_uid(pid, &actual_uid)) return 0;
    return actual_uid == expected_uid;
}

static int process_group_is_alive(pid_t group_id) {
    if (group_id <= 1) return 0;
    if (kill(-group_id, 0) == 0) return 1;
    return errno == EPERM;
}

static int root_worker_security_error(const char *reason) {
    (void)dprintf(STDERR_FILENO, "root_worker_security_error=%s\n", reason);
    return 77;
}

/* Keep KernelSU-granted root capabilities intact; verify only UID identity. */
static int require_root_identity(void) {
    if (getuid() != 0 || geteuid() != 0) {
        return root_worker_security_error("not_uid_zero");
    }
    return 0;
}

static int install_supervisor_signal_handlers(void) {
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = request_supervisor_stop;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    if (sigaction(SIGTERM, &action, NULL) != 0 ||
        sigaction(SIGINT, &action, NULL) != 0 ||
        sigaction(SIGHUP, &action, NULL) != 0) {
        return 0;
    }
    return 1;
}

/*
 * Root-side supervisor used only behind the fixed KernelSU commands built by
 * Kotlin.  It remains the parent of a private process group even when
 * setuidgid forks and the child is later reparented to init.  The first three
 * arguments are fixed app metadata; the command after `--` is always
 * `/system/bin/sh -c <Kotlin-generated fixed command>`.
 */
static int run_root_supervisor(int argc, char **argv) {
    const int is_proot = argc >= 2 && strcmp(argv[1], "--root-supervisor") == 0;
    const int is_codex_proot = argc >= 2 &&
        strcmp(argv[1], "--root-codex-supervisor") == 0;
    if (argc != 8 || (!is_proot && !is_codex_proot) ||
        strcmp(argv[4], "--") != 0 || strcmp(argv[5], "/system/bin/sh") != 0 ||
        strcmp(argv[6], "-c") != 0 || argv[7] == NULL ||
        strstr(argv[7], "libcodex_proot.so") == NULL ||
        strstr(argv[7], "--kill-on-exit") == NULL) {
        return 64;
    }

    long app_pid_number = 0;
    long app_uid_number = 0;
    if (!parse_positive_number(argv[2], 2, 2147483647L, &app_pid_number) ||
        !parse_positive_number(argv[3], 1, 2147483647L, &app_uid_number)) {
        return 64;
    }
    const pid_t app_pid = (pid_t)app_pid_number;
    const uid_t app_uid = (uid_t)app_uid_number;

    if (is_codex_proot && require_root_identity() != 0) return 77;

    const pid_t parent = getppid();
    if (parent <= 1) return 125;
    if (prctl(PR_SET_PDEATHSIG, SIGTERM) != 0) return 125;
    if (getppid() != parent) return 125;
    if (!install_supervisor_signal_handlers()) return 125;

    sigset_t blocked;
    sigset_t previous;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGTERM);
    sigaddset(&blocked, SIGINT);
    sigaddset(&blocked, SIGHUP);
    if (sigprocmask(SIG_BLOCK, &blocked, &previous) != 0) return 125;

    const pid_t child = fork();
    if (child < 0) {
        (void)sigprocmask(SIG_SETMASK, &previous, NULL);
        return 126;
    }
    if (child == 0) {
        (void)sigprocmask(SIG_SETMASK, &previous, NULL);
        if (setpgid(0, 0) != 0) _exit(125);
        execv(argv[5], &argv[5]);
        _exit(127);
    }

    /* The child is the private group leader; descendants retain this group. */
    (void)setpgid(child, child);
    supervisor_child_pid = child;
    supervisor_group_id = child;
    (void)sigprocmask(SIG_SETMASK, &previous, NULL);

    int child_reaped = 0;
    int child_status = 125;
    long long stop_deadline = 0;
    int kill_sent = 0;
    for (;;) {
        if (!process_is_alive_for_uid(app_pid, app_uid)) {
            supervisor_stop_requested = 1;
        }
        if (getppid() != parent) {
            supervisor_stop_requested = 1;
        }

        if (supervisor_stop_requested && stop_deadline == 0) {
            (void)kill(-child, SIGTERM);
            stop_deadline = monotonic_millis() + 1500;
        }
        if (!child_reaped) {
            const pid_t waited = waitpid(child, &child_status, WNOHANG);
            if (waited == child) {
                child_reaped = 1;
            } else if (waited < 0 && errno != EINTR) {
                child_reaped = 1;
                child_status = 125 << 8;
            }
        }
        if (stop_deadline != 0 && monotonic_millis() >= stop_deadline) {
            (void)kill(-child, SIGKILL);
            kill_sent = 1;
            stop_deadline = monotonic_millis() + 1500;
        }

        if (child_reaped && !process_group_is_alive(child)) break;
        if (kill_sent && !process_group_is_alive(child)) break;
        sleep_millis(50);
    }

    if (!child_reaped) {
        while (waitpid(child, &child_status, 0) < 0 && errno == EINTR) {
            /* Keep reaping the fixed child. */
        }
    }
    supervisor_child_pid = -1;
    supervisor_group_id = -1;
    return child_exit_code(child_status);
}

static int run_root_profile_probe(int argc, char **argv) {
    if (argc != 6 || strcmp(argv[1], "--root-codex-profile-probe") != 0 ||
        strcmp(argv[2], "--") != 0 || strcmp(argv[3], "/system/bin/sh") != 0 ||
        strcmp(argv[4], "-c") != 0 || argv[5] == NULL || argv[5][0] == '\0') {
        return 64;
    }

    const pid_t parent = getppid();
    if (parent <= 1 || prctl(PR_SET_PDEATHSIG, SIGTERM) != 0 || getppid() != parent) {
        return 125;
    }
    if (require_root_identity() != 0) return 77;

    execv(argv[3], &argv[3]);
    return 127;
}

int main(int argc, char **argv) {
    if (argc >= 2 && argv[1] != NULL &&
        (strcmp(argv[1], "--root-supervisor") == 0 ||
         strcmp(argv[1], "--root-codex-supervisor") == 0)) {
        return run_root_supervisor(argc, argv);
    }
    if (argc >= 2 && argv[1] != NULL &&
        strcmp(argv[1], "--root-codex-profile-probe") == 0) {
        return run_root_profile_probe(argc, argv);
    }
    if (argc < 2 || argv[1] == NULL || argv[1][0] != '/') return 64;

    /* The guard must be a direct child of the Android app. */
    const pid_t parent = getppid();
    if (parent <= 1) return 125;
    if (prctl(PR_SET_PDEATHSIG, SIGTERM) != 0) return 125;
    if (getppid() != parent) return 125;

    struct sigaction action;
    action.sa_handler = request_stop;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    if (sigaction(SIGTERM, &action, NULL) != 0 ||
        sigaction(SIGINT, &action, NULL) != 0 ||
        sigaction(SIGHUP, &action, NULL) != 0) {
        return 125;
    }

    /* Do not let a parent-death signal arrive between fork and child_pid. */
    sigset_t blocked;
    sigset_t previous;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGTERM);
    sigaddset(&blocked, SIGINT);
    sigaddset(&blocked, SIGHUP);
    if (sigprocmask(SIG_BLOCK, &blocked, &previous) != 0) return 125;

    const pid_t child = fork();
    if (child < 0) {
        (void)sigprocmask(SIG_SETMASK, &previous, NULL);
        return 126;
    }
    if (child == 0) {
        (void)sigprocmask(SIG_SETMASK, &previous, NULL);
        execv(argv[1], &argv[1]);
        _exit(127);
    }

    child_pid = child;
    (void)sigprocmask(SIG_SETMASK, &previous, NULL);

    long long stop_deadline = 0;
    int status = 125;
    for (;;) {
        /* This also covers unusual termination paths where the death signal
         * is not delivered by the platform. */
        if (getppid() != parent) stop_requested = 1;
        if (stop_requested && stop_deadline == 0) {
            (void)kill(child, SIGTERM);
            stop_deadline = monotonic_millis() + 1500;
        }

        const pid_t waited = waitpid(child, &status, WNOHANG);
        if (waited == child) break;
        if (waited < 0 && errno != EINTR) {
            (void)kill(child, SIGKILL);
            (void)waitpid(child, &status, 0);
            return 125;
        }
        if (stop_deadline != 0 && monotonic_millis() >= stop_deadline) {
            (void)kill(child, SIGKILL);
            stop_deadline = 0;
        }
        sleep_millis(50);
    }

    return child_exit_code(status);
}
