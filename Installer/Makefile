
include theos/makefiles/common.mk

TOOL_NAME = BelfryInstaller BelfryRemover

BelfryInstaller_FILES = Installer.m partial.c
BelfryInstaller_FRAMEWORKS = Foundation CoreFoundation
BelfryInstaller_LDFLAGS = -lcurl -lz
BelfryInstaller_OBJCFLAGS = -I$(THEOS_PROJECT_DIR) -F$(THEOS_PROJECT_DIR)

BelfryRemover_FILES = Remover.m
BelfryRemover_FRAMEWORKS = Foundation CoreFoundation
BelfryRemover_OBJCFLAGS = -I$(THEOS_PROJECT_DIR) -F$(THEOS_PROJECT_DIR)

include $(THEOS_MAKE_PATH)/tool.mk

