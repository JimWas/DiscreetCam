# Off-device logic tests for the JWR recorder modules. Build with GNUstep:
#   . /usr/share/GNUstep/Makefiles/GNUstep.sh   (or wherever GNUstep.sh lives)
#   make -C tests
# or simply run:  bash tests/run.sh

include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = jwr-logic-tests

jwr-logic-tests_OBJC_FILES = \
	main.m \
	JWRLogicTests.m \
	JWRTestSupport.m \
	JWRMovieValidationStub.m \
	JWRPreferencesStub.m \
	../JWROutputFiles.m \
	../JWRButtonRouter.m \
	../JWRPreferences+Normalization.m \
	../JWRLogger.m

jwr-logic-tests_C_FILES = notify_stub.c

jwr-logic-tests_INCLUDE_DIRS = . shim ..
jwr-logic-tests_OBJCFLAGS = -fblocks -fobjc-exceptions
jwr-logic-tests_LDFLAGS = -lBlocksRuntime

include $(GNUSTEP_MAKEFILES)/tool.make
