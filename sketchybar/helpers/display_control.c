/* JSON-only BetterDisplay bridge for the SketchyBar display panel. */
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <json-c/json.h>
#include <math.h>
#include <poll.h>
#include <regex.h>
#include <signal.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;
typedef struct {
    const char *binary;
    double deadline;
    const char *error;
} Client;

static double monotonic(void)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec + now.tv_nsec / 1e9;
}

static void *allocate(size_t size)
{
    void *memory = malloc(size);
    if (!memory) {
        puts("{\"ok\":false,\"error\":\"Out of memory\"}");
        exit(1);
    }
    return memory;
}

static bool fail(Client *client, const char *error)
{
    client->error = error;
    return false;
}

static bool initialize(Client *client, double budget)
{
    client->deadline = monotonic() + budget;
    client->binary = getenv("BETTERDISPLAY_BIN");
    if (client->binary) {
        if (!access(client->binary, X_OK)) return true;
    } else {
        const char *paths[] = {"/opt/homebrew/bin/betterdisplaycli", "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"};
        for (size_t i = 0; i < sizeof(paths) / sizeof(*paths); i++) {
            if (!access(paths[i], X_OK)) { client->binary = paths[i]; return true; }
        }
    }
    return fail(client, "BetterDisplay is not installed");
}

/* Structured argv, a 1.2s per-command cap, and one shared operation deadline. */
static bool run(Client *client, const char *const arguments[], char **output)
{
    double now = monotonic(), deadline = fmin(client->deadline, now + 1.2);
    if (now >= deadline) return fail(client, "BetterDisplay did not respond in time");
    char *argv[16] = {(char *)client->binary};
    size_t argc = 1;
    for (size_t i = 0; arguments[i]; i++) {
        if (argc >= 15) return fail(client, "Invalid BetterDisplay command");
        argv[argc++] = (char *)arguments[i];
    }
    int pipes[2];
    if (pipe(pipes)) return fail(client, "Could not contact BetterDisplay");
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipes[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipes[0]);
    posix_spawn_file_actions_addclose(&actions, pipes[1]);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
    pid_t pid;
    int spawned = posix_spawn(&pid, client->binary, &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(pipes[1]);
    if (spawned) { close(pipes[0]); return fail(client, "Could not contact BetterDisplay"); }
    fcntl(pipes[0], F_SETFL, O_NONBLOCK);
    size_t length = 0, capacity = 4096;
    char *buffer = allocate(capacity);
    bool eof = false, exited = false, success = true;
    int status = 0;
    while (!eof || !exited) {
        if (monotonic() >= deadline) { success = fail(client, "BetterDisplay did not respond in time"); break; }
        if (!eof) {
            if (length + 1 == capacity) {
                if (capacity >= 4 * 1024 * 1024) { success = fail(client, "BetterDisplay response is too large"); break; }
                char *grown = realloc(buffer, capacity * 2);
                if (!grown) { success = fail(client, "Out of memory"); break; }
                buffer = grown;
                capacity *= 2;
            }
            ssize_t count = read(pipes[0], buffer + length, capacity - length - 1);
            if (count > 0) { length += (size_t)count; continue; }
            if (!count) eof = true;
            else if (errno != EAGAIN && errno != EINTR) { success = fail(client, "Could not contact BetterDisplay"); break; }
        }
        if (!exited) {
            pid_t waited = waitpid(pid, &status, WNOHANG);
            if (waited == pid) exited = true;
            else if (waited < 0 && errno != EINTR) { success = fail(client, "Could not contact BetterDisplay"); break; }
        }
        if (!eof) {
            struct pollfd descriptor = {.fd = pipes[0], .events = POLLIN};
            poll(&descriptor, 1, 5);
        } else if (!exited) {
            struct timespec delay = {.tv_nsec = 1000000};
            nanosleep(&delay, NULL);
        }
    }
    close(pipes[0]);
    if (!exited) {
        kill(pid, SIGKILL);
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    }
    buffer[length] = '\0';
    if (success && (!WIFEXITED(status) || WEXITSTATUS(status))) {
        success = fail(client, strstr(buffer, "Pro required") ? "BetterDisplay Pro is required" :
                       "BetterDisplay command failed · open BetterDisplay");
    }
    if (success && memchr(buffer, '\0', length)) success = fail(client, "BetterDisplay returned invalid data");
    if (!success) { free(buffer); return false; }
    while (length && isspace((unsigned char)buffer[length - 1])) buffer[--length] = '\0';
    char *start = buffer;
    while (isspace((unsigned char)*start)) start++;
    memmove(buffer, start, strlen(start) + 1);
    *output = buffer;
    return true;
}

static const char *string_field(json_object *object, const char *key)
{
    json_object *value;
    if (!json_object_object_get_ex(object, key, &value) || !json_object_is_type(value, json_type_string)) return NULL;
    const char *string = json_object_get_string(value);
    return strlen(string) == (size_t)json_object_get_string_len(value) ? string : NULL;
}

static bool uuid(const char *input, char output[37])
{
    if (!input || strlen(input) != 36) return false;
    for (size_t i = 0; i < 36; i++) {
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            if (input[i] != '-') return false;
        } else if (!isxdigit((unsigned char)input[i])) return false;
        output[i] = (char)toupper((unsigned char)input[i]);
    }
    output[36] = '\0';
    return true;
}

static bool contains(json_object *displays, const char *identity)
{
    for (size_t i = 0; i < json_object_array_length(displays); i++) {
        if (!strcmp(string_field(json_object_array_get_idx(displays, i), "uuid"), identity)) return true;
    }
    return false;
}

static json_object *identifiers(Client *client, const char *raw)
{
    size_t length = strlen(raw);
    char *wrapped = allocate(length + 3);
    if (*raw == '[') memcpy(wrapped, raw, length + 1);
    else snprintf(wrapped, length + 3, "[%s]", raw);
    json_tokener *parser = json_tokener_new();
    if (!parser) { free(wrapped); fail(client, "Out of memory"); return NULL; }
    json_tokener_set_flags(parser, JSON_TOKENER_STRICT | JSON_TOKENER_VALIDATE_UTF8);
    json_object *rows = json_tokener_parse_ex(parser, wrapped, (int)strlen(wrapped) + 1);
    bool valid = json_tokener_get_error(parser) == json_tokener_success && json_object_is_type(rows, json_type_array);
    json_tokener_free(parser);
    free(wrapped);
    if (!valid) {
        if (rows) json_object_put(rows);
        fail(client, "BetterDisplay returned invalid display data"); return NULL;
    }
    json_object *result = json_object_new_array();
    for (size_t i = 0; i < json_object_array_length(rows); i++) {
        json_object *row = json_object_array_get_idx(rows, i), *id;
        char identity[37];
        if (!json_object_is_type(row, json_type_object)) continue;
        const char *type = string_field(row, "deviceType");
        if (!type || strcmp(type, "Display") || !uuid(string_field(row, "UUID"), identity) || contains(result, identity)) continue;
        if (!json_object_object_get_ex(row, "displayID", &id)) continue;
        if (!json_object_is_type(id, json_type_string) && !json_object_is_type(id, json_type_int)) continue;
        const char *display_id = json_object_get_string(id);
        if (!display_id || *display_id < '1' || *display_id > '9') continue;
        bool digits = true;
        for (const char *p = display_id; *p; p++) if (*p < '0' || *p > '9') digits = false;
        errno = 0;
        char *end;
        long long numeric_id = strtoll(display_id, &end, 10);
        if (!digits || *end || errno || numeric_id < 1 ||
            (json_object_is_type(id, json_type_string) && strlen(display_id) != (size_t)json_object_get_string_len(id))) continue;
        const char *name = string_field(row, "name");
        json_object *display = json_object_new_object();
        json_object_object_add(display, "uuid", json_object_new_string(identity));
        json_object_object_add(display, "name", json_object_new_string(name && *name ? name : "Display"));
        json_object_object_add(display, "display_id", json_object_new_int64(numeric_id));
        json_object_array_add(result, display);
    }
    json_object_put(rows);
    return result;
}

static json_object *discover(Client *client, bool mouse)
{
    const char *args[] = {"get", mouse ? "--displayWithMouse" : "--identifiers", mouse ? "--identifiers" : NULL, NULL};
    char *output;
    if (!run(client, args, &output)) return NULL;
    json_object *result = identifiers(client, output);
    free(output);
    return result;
}

static bool number(const char *raw, double *value)
{
    /* Decimal numbers only; strtod also accepts hex, which the CLI does not use. */
    const char *start = raw;
    while (isspace((unsigned char)*start)) start++;
    if (*start == '+' || *start == '-') start++;
    if (!(isdigit((unsigned char)*start) || *start == '.') || strstr(start, "0x") || strstr(start, "0X")) return false;
    char *end;
    *value = strtod(raw, &end);
    if (end == raw || !isfinite(*value)) return false;
    while (isspace((unsigned char)*end)) end++;
    return !*end;
}

static bool brightness(Client *client, const char *raw, double *value)
{
    if (!number(raw, value)) return fail(client, "BetterDisplay returned invalid brightness");
    if (*value < 0 || *value > 1) return fail(client, "Brightness is outside the supported 0–100% range");
    *value = nearbyint(*value * 100000) / 1000;
    return true;
}

static bool read_feature(Client *client, const char *identity, const char *feature, char **output)
{
    char target[48], option[64];
    snprintf(target, sizeof(target), "--UUID=%s", identity);
    snprintf(option, sizeof(option), "--%s", feature);
    const char *args[] = {"get", target, option, NULL};
    return run(client, args, output);
}

static bool matches(const char *raw, const char *pattern)
{
    regex_t expression;
    if (regcomp(&expression, pattern, REG_EXTENDED | REG_NOSUB)) return false;
    bool valid = !regexec(&expression, raw, 0, NULL, 0);
    regfree(&expression);
    return valid;
}

static json_object *snapshot(Client *client, bool details)
{
    json_object *displays = discover(client, false);
    if (!displays) return NULL;
    for (size_t i = 0; i < json_object_array_length(displays); i++) {
        json_object *display = json_object_array_get_idx(displays, i);
        const char *identity = string_field(display, "uuid");
        char *output;
        double value;
        json_object *level = NULL;
        if (read_feature(client, identity, "brightness", &output)) {
            if (brightness(client, output, &value)) level = json_object_new_double(value);
            free(output);
        }
        json_object_object_add(display, "brightness", level);
        if (!details) continue;
        const char *features[] = {"resolution", "refreshRate"};
        const char *keys[] = {"resolution", "refresh_rate"};
        const char *patterns[] = {"^[1-9][0-9]*x[1-9][0-9]*$",
            "^([0-9]+(\\.[0-9]+)?(-[0-9]+(\\.[0-9]+)?)?Hz(-VRR)?|ProMotion)$"};
        for (size_t k = 0; k < 2; k++) {
            json_object *field = NULL;
            if (read_feature(client, identity, features[k], &output)) {
                if (matches(output, patterns[k])) field = json_object_new_string(output);
                free(output);
            }
            json_object_object_add(display, keys[k], field);
        }
    }
    json_object *mouse_uuid = NULL;
    if (details) {
        json_object *under_mouse = discover(client, true);
        if (under_mouse) {
            if (json_object_array_length(under_mouse) == 1) {
                const char *identity = string_field(json_object_array_get_idx(under_mouse, 0), "uuid");
                if (contains(displays, identity)) mouse_uuid = json_object_new_string(identity);
            }
            json_object_put(under_mouse);
        }
    }
    json_object *result = json_object_new_object();
    json_object_object_add(result, "ok", json_object_new_boolean(true));
    json_object_object_add(result, "displays", displays);
    json_object_object_add(result, "mouse_uuid", mouse_uuid);
    return result;
}

static bool set_brightness(Client *client, const char *identity, double percentage, double *actual)
{
    json_object *displays = discover(client, false);
    if (!displays) return false;
    bool connected = contains(displays, identity);
    json_object_put(displays);
    if (!connected) return fail(client, "Selected display is no longer connected");
    char target[48];
    snprintf(target, sizeof(target), "--UUID=%s", identity);
    const char *range_args[] = {"get", target, "--brightness", "--value", "--min", "--max", NULL};
    char *output;
    if (!run(client, range_args, &output)) return false;
    double bounds[3];
    char *part = output;
    bool valid = true;
    for (size_t i = 0; i < 3; i++) {
        char *comma = strchr(part, ',');
        if ((i < 2 && !comma) || (i == 2 && comma)) { valid = false; break; }
        if (comma) *comma = '\0';
        if (!number(part, &bounds[i])) { valid = false; break; }
        if (comma) part = comma + 1;
    }
    free(output);
    if (!valid) return fail(client, "BetterDisplay did not report a valid brightness range");
    double current = bounds[0], lower = bounds[1], upper = bounds[2];
    if (!(0 <= lower && lower <= current && current <= upper && upper <= 1))
        return fail(client, "Brightness is outside the supported 0–100% range");
    *actual = nearbyint(current * 100000) / 1000;
    if (percentage < lower * 100 || percentage > upper * 100)
        return fail(client, "Brightness is outside this display’s supported range");
    char setting[64];
    snprintf(setting, sizeof(setting), "--brightness=%.6g%%", percentage);
    const char *set_args[] = {"set", target, setting, NULL};
    if (!run(client, set_args, &output)) return false;
    free(output);
    for (size_t attempt = 0; attempt < 3; attempt++) {
        if (read_feature(client, identity, "brightness", &output)) {
            double value;
            bool verified = brightness(client, output, &value);
            free(output);
            if (verified) {
                *actual = value;
                if (fabs(value - percentage) <= 1) return true;
            }
        }
        if (attempt < 2 && client->deadline - monotonic() > 0.15) {
            struct timespec delay = {.tv_nsec = 150000000};
            while (nanosleep(&delay, &delay) && errno == EINTR) {}
        }
    }
    return fail(client, "Brightness change could not be verified · refresh or use BetterDisplay");
}

int main(int argc, char **argv)
{
    Client client = {0};
    json_object *result = NULL;
    if (argc == 2 && (!strcmp(argv[1], "snapshot") || !strcmp(argv[1], "levels"))) {
        if (initialize(&client, 8)) result = snapshot(&client, !strcmp(argv[1], "snapshot"));
    } else if (argc == 4 && !strcmp(argv[1], "brightness")) {
        char identity[37];
        double percentage;
        if (!uuid(argv[2], identity)) fail(&client, "Invalid display identifier");
        else if (!number(argv[3], &percentage)) fail(&client, "BetterDisplay returned invalid brightness");
        else if (percentage < 0 || percentage > 100) fail(&client, "Brightness must be between 0 and 100%");
        else if (initialize(&client, 6)) {
            double actual = NAN;
            bool success = set_brightness(&client, identity, percentage, &actual);
            result = json_object_new_object();
            json_object_object_add(result, "ok", json_object_new_boolean(success));
            if (!success) json_object_object_add(result, "error", json_object_new_string(client.error));
            json_object_object_add(result, "uuid", json_object_new_string(identity));
            json_object_object_add(result, "brightness", isfinite(actual) ? json_object_new_double(actual) : NULL);
        }
    } else fail(&client, "Usage: display-control snapshot | levels | brightness UUID PERCENT");
    if (!result) {
        result = json_object_new_object();
        json_object_object_add(result, "ok", json_object_new_boolean(false));
        json_object_object_add(result, "error", json_object_new_string(client.error));
    }
    json_object *ok;
    json_object_object_get_ex(result, "ok", &ok);
    int status = json_object_get_boolean(ok) ? 0 : 1;
    puts(json_object_to_json_string_ext(result, JSON_C_TO_STRING_PLAIN));
    json_object_put(result);
    return status;
}
