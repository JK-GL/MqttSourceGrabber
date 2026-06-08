ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MqttSourceGrabber

MqttSourceGrabber_FILES = Tweak.x
MqttSourceGrabber_CFLAGS = -fobjc-arc
MqttSourceGrabber_FRAMEWORKS = UIKit Foundation Security

include $(THEOS_MAKE_PATH)/tweak.mk
