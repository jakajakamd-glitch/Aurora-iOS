// log.h — minimal logging stub for the modified Luau VM.
#pragma once

#include <stdio.h>

#define LOGD(fmt, ...)  ((void)0)
#define LOGI(fmt, ...)  ((void)0)
#define LOGW(fmt, ...)  ((void)0)
#define LOGE(fmt, ...)  ((void)0)

#define LUAU_LOG(fmt, ...)  ((void)0)
#define LUAU_LOG_INFO(fmt, ...)  ((void)0)
#define LUAU_LOG_WARN(fmt, ...)  ((void)0)
#define LUAU_LOG_ERROR(fmt, ...) ((void)0)
