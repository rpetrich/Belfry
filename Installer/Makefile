
include theos/makefiles/common.mk

TOOL_NAME = SpireInstaller SpireRemover

SpireInstaller_FILES = Installer.m partial.c
SpireInstaller_FRAMEWORKS = Foundation CoreFoundation
SpireInstaller_LDFLAGS = -lcurl -lz
SpireInstaller_OBJCFLAGS = -I$(THEOS_PROJECT_DIR) -F$(THEOS_PROJECT_DIR)

SpireRemover_FILES = Remover.m
SpireRemover_FRAMEWORKS = Foundation CoreFoundation
SpireRemover_OBJCFLAGS = -I$(THEOS_PROJECT_DIR) -F$(THEOS_PROJECT_DIR)

include $(THEOS_MAKE_PATH)/tool.mk

