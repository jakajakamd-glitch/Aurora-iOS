TARGET := iphone:clang:latest:7.0
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk
LIBRARY_NAME = Aurora
Aurora_FILES = Aurora.mm managers.mm hook_mgr.mm function_mgr.mm \
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
        vendor/Dobby/builtin-plugin/SymbolResolver/macho/shared_cache_ctx.cpp
Aurora_CFLAGS = -fobjc-arc -fvisibility=hidden -DDOBBY_LOGGING_DISABLE -DBUILD_WITH_TRAMPOLINE_ASM \
        -I$(THEOS_PROJECT_DIR)/vendor/Dobby \
        -I$(THEOS_PROJECT_DIR)/vendor/Dobby/include \
        -I$(THEOS_PROJECT_DIR)/vendor/Dobby/source \
        -I$(THEOS_PROJECT_DIR)/vendor/Dobby/source/dobby \
        -I$(THEOS_PROJECT_DIR)/vendor/Dobby/external \
        -I$(THEOS_PROJECT_DIR)/vendor/Dobby/external/logging \
        -I$(THEOS_PROJECT_DIR)/vendor/Dobby/builtin-plugin \
        -I$(THEOS_PROJECT_DIR)/vendor/Dobby/builtin-plugin/SymbolResolver \
        -I$(THEOS_PROJECT_DIR)/vendor/Dobby/source/Backend/UserMode
Aurora_CCFLAGS = -std=c++17 -Wno-reorder-ctor -Wno-sometimes-uninitialized -Wno-unused-variable -Wno-unused-function -Wno-macro-redefined -Wno-logical-op-parentheses -I$(THEOS_PROJECT_DIR)/vendor/Dobby -I$(THEOS_PROJECT_DIR)/vendor/Dobby/include -I$(THEOS_PROJECT_DIR)/vendor/Dobby/source -I$(THEOS_PROJECT_DIR)/vendor/Dobby/source/dobby -I$(THEOS_PROJECT_DIR)/vendor/Dobby/external -I$(THEOS_PROJECT_DIR)/vendor/Dobby/external/logging -I$(THEOS_PROJECT_DIR)/vendor/Dobby/builtin-plugin -I$(THEOS_PROJECT_DIR)/vendor/Dobby/builtin-plugin/SymbolResolver -I$(THEOS_PROJECT_DIR)/vendor/Dobby/source/Backend/UserMode
Aurora_FRAMEWORKS = Foundation
include $(THEOS)/makefiles/library.mk
