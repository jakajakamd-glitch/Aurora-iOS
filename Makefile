TARGET := iphone:clang:latest:16.5
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk
LIBRARY_NAME = Aurora
Aurora_FILES = Aurora.mm managers.mm hook_mgr.mm function_mgr.mm Roblox.mm \
        vendor/Dobby/source/core/assembler/assembler-arm.cc \
        vendor/Dobby/source/core/assembler/assembler-ia32.cc \
        vendor/Dobby/source/core/assembler/assembler-x64.cc \
        vendor/Dobby/source/core/codegen/codegen-arm.cc \
        vendor/Dobby/source/core/codegen/codegen-ia32.cc \
        vendor/Dobby/source/InstructionRelocation/arm/InstructionRelocationARM.cc \
        vendor/Dobby/source/InstructionRelocation/arm64/InstructionRelocationARM64.cc \
        vendor/Dobby/source/InstructionRelocation/x86/InstructionRelocationX86.cc \
        vendor/Dobby/source/InstructionRelocation/x86/InstructionRelocationX86Shared.cc \
        vendor/Dobby/source/InstructionRelocation/x64/InstructionRelocationX64.cc \
        vendor/Dobby/source/InstructionRelocation/x86/x86_insn_decode/x86_insn_decode.c \
        vendor/Dobby/source/InterceptRouting/InstrumentRouting/instrument_routing_handler.cpp \
        vendor/Dobby/source/TrampolineBridge/Trampoline/trampoline_arm.cc \
        vendor/Dobby/source/TrampolineBridge/Trampoline/trampoline_arm64.cc \
        vendor/Dobby/source/TrampolineBridge/Trampoline/trampoline_x86.cc \
        vendor/Dobby/source/TrampolineBridge/Trampoline/trampoline_x64.cc \
        vendor/Dobby/source/TrampolineBridge/ClosureTrampolineBridge/arm64/helper_arm64.cc \
        vendor/Dobby/source/TrampolineBridge/ClosureTrampolineBridge/arm64/closure_bridge_arm64.cc \
        vendor/Dobby/source/TrampolineBridge/ClosureTrampolineBridge/arm64/ClosureTrampolineARM64.cc \
        vendor/Dobby/source/TrampolineBridge/ClosureTrampolineBridge/arm64/closure_bridge_arm64.S \
        vendor/Dobby/source/TrampolineBridge/ClosureTrampolineBridge/arm64/closure_trampoline_arm64.S \
        vendor/Dobby/source/dobby.cpp \
        vendor/Dobby/source/Backend/UserMode/PlatformUtil/Darwin/ProcessRuntime.cc \
        vendor/Dobby/source/Backend/UserMode/UnifiedInterface/platform-posix.cc \
        vendor/Dobby/source/Backend/UserMode/ExecMemory/code-patch-tool-darwin.cc \
        vendor/Dobby/source/Backend/UserMode/ExecMemory/clear-cache-tool-all.c \
        vendor/Dobby/source/InterceptRouting/NearBranchTrampoline/near_trampoline_arm64.cc \
        vendor/Dobby/external/logging/logging.cc \
        vendor/Dobby/builtin-plugin/SymbolResolver/macho/macho_ctx.cc \
        vendor/Dobby/builtin-plugin/SymbolResolver/macho/dobby_symbol_resolver.cc \
        vendor/Dobby/builtin-plugin/SymbolResolver/macho/macho_file_symbol_resolver.cpp \
        vendor/Dobby/builtin-plugin/SymbolResolver/macho/shared_cache_ctx.cpp \
        vendor/Luau/VM/src/lapi.cpp \
        vendor/Luau/VM/src/laux.cpp \
        vendor/Luau/VM/src/lbaselib.cpp \
        vendor/Luau/VM/src/lbitlib.cpp \
        vendor/Luau/VM/src/lbuffer.cpp \
        vendor/Luau/VM/src/lbuflib.cpp \
        vendor/Luau/VM/src/lbuiltins.cpp \
        vendor/Luau/VM/src/lclass.cpp \
        vendor/Luau/VM/src/lclasslib.cpp \
        vendor/Luau/VM/src/lcorolib.cpp \
        vendor/Luau/VM/src/ldblib.cpp \
        vendor/Luau/VM/src/ldebug.cpp \
        vendor/Luau/VM/src/ldo.cpp \
        vendor/Luau/VM/src/lfunc.cpp \
        vendor/Luau/VM/src/lgc.cpp \
        vendor/Luau/VM/src/lgcdebug.cpp \
        vendor/Luau/VM/src/linit.cpp \
        vendor/Luau/VM/src/lintlib.cpp \
        vendor/Luau/VM/src/lmathlib.cpp \
        vendor/Luau/VM/src/lmem.cpp \
        vendor/Luau/VM/src/lnumprint.cpp \
        vendor/Luau/VM/src/lobject.cpp \
        vendor/Luau/VM/src/loslib.cpp \
        vendor/Luau/VM/src/lperf.cpp \
        vendor/Luau/VM/src/lstate.cpp \
        vendor/Luau/VM/src/lstring.cpp \
        vendor/Luau/VM/src/lstrlib.cpp \
        vendor/Luau/VM/src/ltable.cpp \
        vendor/Luau/VM/src/ltablib.cpp \
        vendor/Luau/VM/src/ltm.cpp \
        vendor/Luau/VM/src/ludata.cpp \
        vendor/Luau/VM/src/lutf8lib.cpp \
        vendor/Luau/VM/src/lveclib.cpp \
        vendor/Luau/VM/src/lvector.cpp \
        vendor/Luau/VM/src/lvmexecute.cpp \
        vendor/Luau/VM/src/lvmload.cpp \
        vendor/Luau/VM/src/lvmutils.cpp \
        vendor/Luau/Common/src/BytecodeWire.cpp \
        vendor/Luau/Common/src/StringUtils.cpp \
        vendor/Luau/Common/src/TimeTrace.cpp
Aurora_CFLAGS = -fobjc-arc -fvisibility=hidden -DDOBBY_LOGGING_DISABLE -DBUILD_WITH_TRAMPOLINE_ASM \
        -I$(THEOS_PROJECT_DIR)/vendor/Dobby \
        -I$(THEOS_PROJECT_DIR)/vendor/Dobby/include \
        -I$(THEOS_PROJECT_DIR)/vendor/Dobby/source \
        -I$(THEOS_PROJECT_DIR)/vendor/Dobby/source/dobby \
        -I$(THEOS_PROJECT_DIR)/vendor/Dobby/external \
        -I$(THEOS_PROJECT_DIR)/vendor/Dobby/external/logging \
        -I$(THEOS_PROJECT_DIR)/vendor/Dobby/builtin-plugin \
        -I$(THEOS_PROJECT_DIR)/vendor/Dobby/builtin-plugin/SymbolResolver \
        -I$(THEOS_PROJECT_DIR)/vendor/Dobby/source/Backend/UserMode \
        -I$(THEOS_PROJECT_DIR)/vendor/Luau/VM/include \
        -I$(THEOS_PROJECT_DIR)/vendor/Luau/VM/src \
        -I$(THEOS_PROJECT_DIR)/vendor/Luau/Common/include/Luau
Aurora_CCFLAGS = -std=c++17 -Wno-reorder-ctor -Wno-sometimes-uninitialized -Wno-unused-variable -Wno-unused-function -Wno-macro-redefined -Wno-logical-op-parentheses -I$(THEOS_PROJECT_DIR)/vendor/Dobby -I$(THEOS_PROJECT_DIR)/vendor/Dobby/include -I$(THEOS_PROJECT_DIR)/vendor/Dobby/source -I$(THEOS_PROJECT_DIR)/vendor/Dobby/source/dobby -I$(THEOS_PROJECT_DIR)/vendor/Dobby/external -I$(THEOS_PROJECT_DIR)/vendor/Dobby/external/logging -I$(THEOS_PROJECT_DIR)/vendor/Dobby/builtin-plugin -I$(THEOS_PROJECT_DIR)/vendor/Dobby/builtin-plugin/SymbolResolver -I$(THEOS_PROJECT_DIR)/vendor/Dobby/source/Backend/UserMode -I$(THEOS_PROJECT_DIR)/vendor/Luau/VM/include -I$(THEOS_PROJECT_DIR)/vendor/Luau/VM/src -I$(THEOS_PROJECT_DIR)/vendor/Luau/Common/include -I$(THEOS_PROJECT_DIR)/vendor/Luau/Common/include/Luau
Aurora_FRAMEWORKS = Foundation
include $(THEOS)/makefiles/library.mk
