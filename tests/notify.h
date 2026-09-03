#ifndef JWR_NOTIFY_STUB_H
#define JWR_NOTIFY_STUB_H
// Stand-in for Darwin's <notify.h>, which is not available in the GNUstep
// test environment. Tests never rely on Darwin notification delivery.
int notify_post(const char *name);
#endif
