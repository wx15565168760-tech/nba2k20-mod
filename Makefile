# NBA2K20 Mod Menu - Theos Makefile
# 编译成纯 dylib 库（不含 mobilesubstrate 依赖），供 insert_dylib 注入 TrollStore 应用
# 用 GitHub Actions 在 macOS runner 上编译，产物: nba2k20mod.dylib

export TARGET := iphone:clang:16.5:14.0
export ARCHS := arm64
export DEBUG := 0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = nba2k20mod

nba2k20mod_FILES = Tweak.m
nba2k20mod_CFLAGS = -fobjc-arc -Wno-unused-variable
nba2k20mod_LDFLAGS = -lobjc
nba2k20mod_INSTALL_PATH = /usr/lib

include $(THEOS_MAKE_PATH)/library.mk
