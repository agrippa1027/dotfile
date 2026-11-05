/* Keep ordinary Spaces ordered on their current displays. */
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <json-c/json.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;
static const char *binary;
static char error[512];

typedef struct {
    int64_t id, index, display;
    const char *label;
    bool fullscreen;
} Space;

typedef struct {
    json_object *json;
    Space *spaces;
    size_t count;
} Report;

static int fail(const char *message)
{
    snprintf(error, sizeof(error), "%s", message);
    return -1;
}

static double monotonic(void)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec + now.tv_nsec / 1e9;
}

/* No shell; bound both the response size and the lifetime of every child. */
static int command(char *const args[], char **output)
{
    int pipes[2], status = 0;
    if (pipe(pipes)) return fail(strerror(errno));
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipes[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipes[0]);
    posix_spawn_file_actions_addclose(&actions, pipes[1]);
    pid_t pid;
    int spawned = posix_spawn(&pid, binary, &actions, NULL, args, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(pipes[1]);
    if (spawned) { close(pipes[0]); return fail(strerror(spawned)); }
    fcntl(pipes[0], F_SETFL, O_NONBLOCK);
    size_t length = 0, capacity = 4096;
    char *buffer = malloc(capacity);
    bool eof = false, exited = false;
    int result = 0;
    double deadline = monotonic() + 10.0;
    if (!buffer) { result = fail("out of memory"); goto done; }
    while (!eof || !exited) {
        if (monotonic() >= deadline) { result = fail("yabai command timed out"); break; }
        if (!eof) {
            if (length + 1 == capacity) {
                if (capacity >= 16 * 1024 * 1024) { result = fail("yabai response too large"); break; }
                char *grown = realloc(buffer, capacity * 2);
                if (!grown) { result = fail("out of memory"); break; }
                buffer = grown;
                capacity *= 2;
            }
            ssize_t count = read(pipes[0], buffer + length, capacity - length - 1);
            if (count > 0) { length += (size_t)count; continue; }
            if (count == 0) eof = true;
            else if (errno != EAGAIN && errno != EINTR) { result = fail(strerror(errno)); break; }
        }
        if (!exited) {
            pid_t waited = waitpid(pid, &status, WNOHANG);
            if (waited == pid) exited = true;
            else if (waited < 0 && errno != EINTR) { result = fail(strerror(errno)); break; }
        }
        if (!eof) {
            struct pollfd descriptor = {.fd = pipes[0], .events = POLLIN};
            poll(&descriptor, 1, 10);
        } else if (!exited) {
            struct timespec delay = {.tv_nsec = 1000000};
            nanosleep(&delay, NULL);
        }
    }
done:
    close(pipes[0]);
    if (!exited) {
        kill(pid, SIGKILL);
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    }
    if (!result && (!WIFEXITED(status) || WEXITSTATUS(status))) result = fail("yabai command failed (see stderr)");
    if (result) free(buffer);
    else { buffer[length] = '\0'; *output = buffer; }
    return result;
}

static void release_report(Report *report)
{
    free(report->spaces);
    if (report->json) json_object_put(report->json);
    *report = (Report){0};
}

static int index_compare(const void *a, const void *b)
{
    const Space *left = a, *right = b;
    return (left->index > right->index) - (left->index < right->index);
}

static int query(Report *report)
{
    char *output = NULL;
    char *args[] = {(char *)binary, "-m", "query", "--spaces", NULL};
    if (command(args, &output)) return -1;
    json_tokener *parser = json_tokener_new();
    if (!parser) { free(output); return fail("out of memory"); }
    json_tokener_set_flags(parser, JSON_TOKENER_STRICT);
    report->json = json_tokener_parse_ex(parser, output, (int)strlen(output) + 1);
    bool parsed = json_tokener_get_error(parser) == json_tokener_success;
    json_tokener_free(parser);
    free(output);
    if (!parsed || !json_object_is_type(report->json, json_type_array)) goto invalid;
    report->count = json_object_array_length(report->json);
    report->spaces = calloc(report->count + 1, sizeof(Space));
    if (!report->spaces) { release_report(report); return fail("out of memory"); }
    for (size_t i = 0; i < report->count; i++) {
        json_object *row = json_object_array_get_idx(report->json, i), *value;
        if (!json_object_is_type(row, json_type_object)) goto invalid;
        const char *keys[] = {"id", "index", "display"};
        int64_t *values[] = {&report->spaces[i].id, &report->spaces[i].index, &report->spaces[i].display};
        for (size_t k = 0; k < 3; k++) {
            if (!json_object_object_get_ex(row, keys[k], &value) ||
                !json_object_is_type(value, json_type_int) || json_object_get_int64(value) < 1) goto invalid;
            *values[k] = json_object_get_int64(value);
        }
        if (!json_object_object_get_ex(row, "label", &value) || !json_object_is_type(value, json_type_string)) goto invalid;
        report->spaces[i].label = json_object_get_string(value);
        if (strlen(report->spaces[i].label) != (size_t)json_object_get_string_len(value)) goto invalid;
        if (!json_object_object_get_ex(row, "is-native-fullscreen", &value) || !json_object_is_type(value, json_type_boolean)) goto invalid;
        report->spaces[i].fullscreen = json_object_get_boolean(value);
        for (size_t j = 0; j < i; j++) {
            if (report->spaces[j].id == report->spaces[i].id || report->spaces[j].index == report->spaces[i].index) goto invalid;
        }
    }
    qsort(report->spaces, report->count, sizeof(Space), index_compare);
    return 0;
invalid:
    release_report(report);
    return fail("invalid yabai Space report");
}

static int rank(const Space *space)
{
    const char *labels = "1234567890a", *position;
    if (strlen(space->label) == 4 && !strncmp(space->label, "ws-", 3) &&
        (position = strchr(labels, space->label[3]))) return (int)(position - labels);
    return 11;
}

static int desired_compare(const void *a, const void *b)
{
    const Space *left = *(const Space *const *)a, *right = *(const Space *const *)b;
    if (left->display != right->display) return (left->display > right->display) - (left->display < right->display);
    if (rank(left) != rank(right)) return rank(left) - rank(right);
    return index_compare(left, right); /* Stable order for equal/unmanaged labels. */
}

static int plan(const Report *report, bool dry_run, int64_t *source, int64_t *destination)
{
    const Space **desired = calloc(report->count + 1, sizeof(Space *));
    if (!desired) return fail("out of memory");
    size_t count = 0;
    for (size_t i = 0; i < report->count; i++) if (!report->spaces[i].fullscreen) desired[count++] = &report->spaces[i];
    qsort(desired, count, sizeof(Space *), desired_compare);
    *source = *destination = 0;
    int64_t display = 0;
    for (size_t i = 0; i < count; i++) {
        const Space *wanted = desired[i];
        if (dry_run) {
            if (wanted->display != display) {
                if (display) putchar('\n');
                display = wanted->display;
                printf("Display %" PRId64 ":", display);
            }
            printf(" %s#%" PRId64, *wanted->label ? wanted->label : "unlabeled", wanted->id);
        } else {
            /* Find the corresponding ordinary slot on this display. */
            size_t slot = 0, offset = i;
            while (offset && desired[offset - 1]->display == wanted->display) offset--;
            for (size_t j = 0; j < report->count; j++) {
                const Space *actual = &report->spaces[j];
                if (actual->display != wanted->display || actual->fullscreen) continue;
                if (slot++ != i - offset) continue;
                if (actual->id != wanted->id) { *source = wanted->id; *destination = actual->id; }
                break;
            }
            if (*source) break;
        }
    }
    if (dry_run && display) putchar('\n');
    free(desired);
    return 0;
}

static bool same_topology(const Report *a, const Report *b)
{
    if (a->count != b->count) return false;
    for (size_t i = 0; i < a->count; i++) {
        const Space *x = &a->spaces[i], *y = &b->spaces[i];
        if (x->id != y->id || x->index != y->index || x->display != y->display ||
            x->fullscreen != y->fullscreen || strcmp(x->label, y->label)) return false;
    }
    return true;
}

static int reconcile(void)
{
    Report spaces = {0};
    if (query(&spaces)) return -1;
    size_t limit = spaces.count * 8 > 16 ? spaces.count * 8 : 16, moved = 0;
    int result = -1;
    for (size_t attempt = 0; attempt < limit; attempt++) {
        int64_t source, destination;
        Report latest = {0};
        if (plan(&spaces, false, &source, &destination) || query(&latest)) break;
        bool unchanged = same_topology(&spaces, &latest);
        release_report(&spaces);
        spaces = latest;
        if (!unchanged) continue;
        if (!source) { result = (int)moved; break; }
        const Space *from = NULL, *to = NULL;
        for (size_t i = 0; i < spaces.count; i++) {
            if (spaces.spaces[i].id == source) from = &spaces.spaces[i];
            if (spaces.spaces[i].id == destination) to = &spaces.spaces[i];
        }
        if (!from || !to || from->display != to->display || from->fullscreen || to->fullscreen) {
            fail("Space topology changed; refusing an unsafe move"); break;
        }
        char source_index[32], target_index[32], *output = NULL;
        snprintf(source_index, sizeof(source_index), "%" PRId64, from->index);
        snprintf(target_index, sizeof(target_index), "%" PRId64, to->index);
        char *args[] = {(char *)binary, "-m", "space", source_index, "--move", target_index, NULL};
        if (command(args, &output)) break;
        free(output);
        moved++;
        release_report(&spaces);
        if (query(&spaces)) break;
    }
    release_report(&spaces);
    if (result < 0 && !*error) fail("Space ordering did not settle; another client may be rearranging Spaces");
    return result;
}

int main(int argc, char **argv)
{
    bool check = argc == 2 && !strcmp(argv[1], "--check");
    bool dry_run = argc == 2 && !strcmp(argv[1], "--dry-run");
    if (argc != 1 && !check && !dry_run) {
        fprintf(stderr, "Usage: %s [--check | --dry-run]\n", argv[0]); return 2;
    }
    binary = getenv("YABAI_BIN");
    if (!binary) binary = "/opt/homebrew/bin/yabai";
    if (check || dry_run) {
        Report report = {0};
        int64_t source = 0, destination = 0;
        int result = query(&report);
        if (!result) result = plan(&report, dry_run, &source, &destination);
        release_report(&report);
        if (!result) return check && source ? 1 : 0;
    } else {
        char path[PATH_MAX];
        const char *tmp = getenv("TMPDIR");
        if (!tmp || !*tmp) tmp = "/tmp";
        int length = snprintf(path, sizeof(path), "%s/yabai-space-order-%u.lock", tmp, (unsigned)getuid());
        if (length < 0 || (size_t)length >= sizeof(path)) { fail("lock path too long"); goto failed; }
        int lock = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
        if (lock < 0) { fail(strerror(errno)); goto failed; }
        struct stat info;
        if (fstat(lock, &info) || !S_ISREG(info.st_mode) || info.st_uid != getuid()) {
            close(lock); fail("unsafe lock file"); goto failed;
        }
        if (flock(lock, LOCK_EX | LOCK_NB)) {
            int saved = errno;
            close(lock);
            if (saved == EWOULDBLOCK) return 0;
            fail(strerror(saved)); goto failed;
        }
        int moved = reconcile();
        close(lock);
        if (moved >= 0) {
            if (moved) printf("Ordered Spaces on their existing displays (%d moves)\n", moved);
            return 0;
        }
    }
failed:
    fprintf(stderr, "Space ordering failed: %s\n", error);
    return 2;
}
