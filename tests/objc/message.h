#ifndef JWR_OBJC_MESSAGE_SHIM
#define JWR_OBJC_MESSAGE_SHIM
// Minimal stand-in for the GNU runtime's <objc/message.h> in case the
// compiler does not add the libobjc header directory to the search path.
#import <objc/objc.h>
id objc_msgSend(id self, SEL op, ...);
#endif
