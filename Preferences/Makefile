
include ../theos/makefiles/common.mk

BUNDLE_NAME = SpirePreferences
SpirePreferences_FILES = Preferences.mm
SpirePreferences_OBJCFLAGS = -I$(THEOS_PROJECT_DIR) -F$(THEOS_PROJECT_DIR)
SpirePreferences_FRAMEWORKS = UIKit
SpirePreferences_PRIVATE_FRAMEWORKS = Preferences
SpirePreferences_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp Spire.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/Spire.plist$(ECHO_END)

