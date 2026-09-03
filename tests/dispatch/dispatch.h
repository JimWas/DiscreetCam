#ifndef JWR_DISPATCH_SHIM_H
#define JWR_DISPATCH_SHIM_H
// Minimal stand-in for libdispatch. This app ships no dispatch machinery of
// its own; the capture manager lives on its own serial queue and the router
// defers only the long-press check. The harness overrides the router's
// performAfterDelay seam, so these shims never execute real work.
#include <stdint.h>

#define NSEC_PER_SEC 1000000000ull
#define DISPATCH_TIME_NOW 0ull

typedef long dispatch_once_t;
typedef unsigned long long dispatch_time_t;
typedef void (^dispatch_block_t)(void);

static inline void dispatch_once(dispatch_once_t *token, dispatch_block_t block) {
    if (!*token) {
        *token = 1;
        block();
    }
}
static inline dispatch_time_t dispatch_time(dispatch_time_t base, int64_t delta) {
    (void)base;
    (void)delta;
    return 0;
}
static inline void dispatch_after(dispatch_time_t when, void *queue, dispatch_block_t block) {
    (void)when;
    (void)queue;
    block();
}
static inline void *dispatch_get_main_queue(void) {
    return (void *)0;
}
static inline void *dispatch_get_global_queue(long priority, unsigned long flags) {
    (void)priority;
    (void)flags;
    return (void *)0;
}
#endif
