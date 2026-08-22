#pragma once

#include "../../obfuscation.hpp"

namespace managers::core {

static auto hookmetamethod_script = OBF(R"AURORA(getgenv().hookmetamethod = function(object, metamethod_name, hook)
    local metatable
    if getrawmetatable then
        metatable = getrawmetatable(object)
    else
        metatable = getmetatable(object)
    end
    if type(metatable) ~= "table" then
        error("object has no accessible metatable", 2)
    end
    local target = rawget(metatable, metamethod_name)
    if type(target) ~= "function" then
        error("metamethod is not a function", 2)
    end
    return hookfunction(target, hook)
end)AURORA");

}
