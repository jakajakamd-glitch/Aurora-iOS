#pragma once

#if defined(__clang__)
#pragma clang diagnostic ignored "-Wformat-security"
#endif

#define OXORANY_USE_BIT_CAST
#include "vendor/oxorany/oxorany.h"

namespace _lxy_oxor_any_ {
inline _lxy__size_t& X() {
    static _lxy__size_t value = 0;
    return value;
}

inline _lxy__size_t& Y() {
    static _lxy__size_t value = 0;
    return value;
}
}

#define OBF(value) oxorany(value)
#define OBF_NS(value) [NSString stringWithUTF8String:OBF(value)]

