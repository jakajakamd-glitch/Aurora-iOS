#pragma once

#include <cstdint>

namespace utility {

class utility_mgr_type {
public:
    void start();
    void log(const char *msg);
};

extern utility_mgr_type utility_mgr;

}
