
include theos/makefiles/common.mk

AGGREGATE_NAME = Spire
SUBPROJECTS = Preferences Installer Hooks Injector

include $(THEOS_MAKE_PATH)/aggregate.mk

