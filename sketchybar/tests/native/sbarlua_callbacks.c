// Compile with -DSBARLUA_SOURCE='".../src/sketchybar.c"' and Lua/CoreFoundation.
// Targets an unregistered Mach service; does not execute shell commands.
#include SBARLUA_SOURCE
#include <assert.h>

static int make_callback(const char* body) {
  assert(luaL_dostring(g_state, body) == LUA_OK);
  assert(lua_isfunction(g_state, -1));
  return luaL_ref(g_state, LUA_REGISTRYINDEX);
}

int main(void) {
  snprintf(g_bs_lookup, sizeof(g_bs_lookup), "git.codex.callback-test.unregistered");
  g_state = luaL_newstate();
  luaL_openlibs(g_state);
  assert(luaL_dostring(g_state,
    "weak = setmetatable({}, {__mode='v'}); calls = 0") == LUA_OK);
  for (int i = 0; i < 1000; i++) {
    int ref = make_callback(
      "local payload = {}; weak[1] = payload; return function(result, status) "
      "assert(result == 'done' and status == 0); calls = calls + 1; "
      "return payload end");
    char message[1 + 2*sizeof(int) + 5] = { '\x07' };
    int code = 0;
    memcpy(message + 1, &ref, sizeof(ref));
    memcpy(message + 1 + sizeof(int), &code, sizeof(code));
    memcpy(message + 1 + 2*sizeof(int), "done", 5);
    callback_function(message, sizeof(message));
    assert(lua_gettop(g_state) == 0);
    lua_gc(g_state, LUA_GCCOLLECT);
    assert(luaL_dostring(g_state, "assert(weak[1] == nil)") == LUA_OK);

    ref = make_callback("local payload = {}; weak[1] = payload; "
                        "return function() return payload end");
    delay_callback(NULL, (void*)(intptr_t)ref);
    assert(lua_gettop(g_state) == 0);
    lua_gc(g_state, LUA_GCCOLLECT);
    assert(luaL_dostring(g_state, "assert(weak[1] == nil)") == LUA_OK);
  }
  int ref = make_callback("return function() error('expected test error') end");
  delay_callback(NULL, (void*)(intptr_t)ref);
  assert(lua_gettop(g_state) == 0);
  assert(luaL_dostring(g_state, "assert(calls == 1000)") == LUA_OK);
  lua_close(g_state);
  puts("PASS: 2000 completed exec/timer closures are collected; callback errors leave no stack entries");
}
