
include theos/makefiles/common.mk

TOOL_NAME = SpireInstaller SpireRemover

SpireInstaller_FILES = Installer.m partial.c
SpireInstaller_FRAMEWORKS = Foundation CoreFoundation
SpireInstaller_LDFLAGS = -lcurl -lz

SpireRemover_FILES = Remover.m
SpireRemover_FRAMEWORKS = Foundation CoreFoundation

include $(THEOS_MAKE_PATH)/tool.mk

