include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MqttSourceGrabber

MqttSourceGrabber_FILES = Tweak.x
MqttSourceGrabber_CFLAGS = -fobjc-arc
MqttSourceGrabber_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
