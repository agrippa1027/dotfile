// Compile with the engine objects and -DSKETCHYBAR_SOURCE='".../src/sketchybar.c"'.
// Uses the actual drawing and hit-test paths without contacting WindowServer.
#define main sketchybar_daemon_main
#include SKETCHYBAR_SOURCE
#undef main
#include <assert.h>

// Exercise popup ordering with WindowServer writes replaced by counters.
static int ordered_windows;
static void test_level(struct window* window, uint32_t level) { }
static void test_order(struct window* window, struct window* parent, int mode) { }
static void test_chain(struct window* root, struct window** chain, int count) {
  ordered_windows = count;
}
#define window_set_level test_level
#define window_order test_order
#define windows_set_order_chain test_chain
#include SKETCHYBAR_POPUP_SOURCE
#undef window_set_level
#undef window_order
#undef windows_set_order_chain

int main(void) {
  struct bar bar = { .sid = 1, .adid = 1, .shown = true };
  struct bar_item parent = {0};
  struct bar_item hidden = { .position = POSITION_POPUP, .drawing = true,
                             .parent = &parent };
  struct bar_item timer = { .drawing = false };
  struct bar_item* items[] = { &hidden, &timer };
  g_bar_manager.bar_items = items;
  g_bar_manager.bar_item_count = 2;
  g_bar_manager.might_need_clipping = true;

  assert(!bar_item_find_window(NULL, 1));
  assert(!bar_item_find_window(&hidden, 0));
  assert(!bar_item_find_window(&hidden, 1));
  for (int i = 0; i < 100; i++) {
    bar_draw(&bar, false);
    assert(!bar_manager_get_item_by_wid(&g_bar_manager, 42, NULL));
    assert(!bar_manager_get_item_by_point(&g_bar_manager,
                                         (CGPoint){100, 100}, NULL));
  }
  assert(hidden.num_windows == 0 && hidden.windows == NULL);
  assert(timer.num_windows == 0 && timer.windows == NULL);

  // A popup opened on display 2 leaves an empty display-1 slot. Pointer
  // lookups must traverse that hole without opening another native window.
  struct window existing = { .id = 42, .origin = {10, 10},
                             .frame = {{0, 0}, {20, 20}} };
  struct window* windows[] = { NULL, &existing };
  hidden.windows = windows;
  hidden.num_windows = 2;
  assert(bar_item_find_window(&hidden, 2) == &existing);
  assert(!bar_item_find_window(&hidden, 3));
  assert(bar_manager_get_item_by_wid(&g_bar_manager, 42, NULL) == &hidden);
  assert(bar_manager_get_item_by_point(&g_bar_manager,
                                       (CGPoint){15, 15}, NULL) == &hidden);
  assert(windows[0] == NULL && hidden.num_windows == 2);

  struct bar_item unseen = {0};
  struct bar_item* popup_items[] = { &unseen, &hidden };
  struct popup popup = { .items = popup_items, .num_items = 2, .adid = 2 };
  popup_order_windows(&popup);
  assert(ordered_windows == 1 && unseen.num_windows == 0 && unseen.windows == NULL);
  assert(windows[0] == NULL);

  for (int i = 0; i < 1000; i++) {
    uint32_t display = i % 2 + 1;
    parent.popup.needs_ordering = hidden.needs_update = false;
    assert(bar_item_get_window(&hidden, display) == &existing);
    assert(windows[display - 1] == &existing && windows[2 - display] == NULL);
    assert(parent.popup.needs_ordering && hidden.needs_update);
    assert(bar_item_get_window_adid(&hidden, &existing) == display);
  }
  puts("PASS: unseen windows stay unallocated; 1000 monitor switches reuse one popup row surface");
}
