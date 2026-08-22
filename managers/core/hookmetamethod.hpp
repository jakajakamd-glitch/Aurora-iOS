#pragma once

#include "../../obfuscation.hpp"

namespace managers::core {

static auto hookmetamethod_script = OBF(R"AURORA(local function getmetatable_for_hook(object)
    if getrawmetatable then
        return getrawmetatable(object)
    end
    return getmetatable(object)
end

function hookmetamethod(object, metamethod_name, hook)
    local metatable = getmetatable_for_hook(object)
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
