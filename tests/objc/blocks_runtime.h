#ifndef JWR_OBJC_BLOCKS_RUNTIME_SHIM
#define JWR_OBJC_BLOCKS_RUNTIME_SHIM
// Ubuntu's libblocksruntime-dev installs a flat Block.h instead of the
// <objc/blocks_runtime.h> that GNUstep's GSVersionMacros expects. Delegate
// to Block.h when present; an empty header still satisfies the include.
#if __has_include(<Block.h>)
#  include <Block.h>
#endif
#endif
