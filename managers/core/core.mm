#import "core.hpp"
#import "../roblox/Roblox.hpp"
#import "../roblox/environment.hpp"
#import "../functions/function_mgr.hpp"
#import "../utility/utility_mgr.hpp"
#import <Foundation/Foundation.h>
#include <cstdint>
#include <atomic>
#include <cstring>
#include <string>
#include "lua.h"
#include "lualib.h"
#include "lmem.h"
#include "lobject.h"
#include "lstate.h"
#include "Luau/Compiler.h"

namespace managers::core {

namespace {

static uint8_t genv_key;
static constexpr uintptr_t actor_global_state_offset = 0x1c8;

struct proto_view {
    uint8_t unknown_00[0x20];
    proto_view** child_protos;
    uint8_t unknown_28[0x10];
    void* capabilities;
    uint8_t unknown_40[0x68];
    uint32_t child_proto_count;
};

struct closure_view {
    uint8_t unknown_00[0x18];
    proto_view* proto;
};

void set_proto_caps(lua_State* l, void* capability_table) {
    if (!l || !capability_table || lua_type(l, -1) != LUA_TFUNCTION) {
        return;
    }

    const void* object = lua_topointer(l, -1);
    if (!object) {
        return;
    }

    closure_view* closure = const_cast<closure_view*>(reinterpret_cast<const closure_view*>(object));
    proto_view* root = closure->proto;
    if (!root || (!root->child_protos && root->child_proto_count != 0)) {
        return;
    }

    root->capabilities = capability_table;
    for (uint32_t i = 0; i < root->child_proto_count; ++i) {
        if (root->child_protos[i]) {
            root->child_protos[i]->capabilities = capability_table;
        }
    }
}

lua_State* actor_global_state(lua_State* L) {
    void* actor = lua_touserdata(L, 1);
    if (!actor) {
        actor = const_cast<void*>(lua_topointer(L, 1));
    }
    if (!actor) {
        return nullptr;
    }

    return *reinterpret_cast<lua_State**>(reinterpret_cast<uint8_t*>(actor) + actor_global_state_offset);
}

lua_State* find_script_thread(lua_State* state, void* script) {
    if (!state || !state->global || !script) {
        return nullptr;
    }

    for (lua_Page* page = state->global->allgcopages; page; page = luaM_getnextpage(page)) {
        char* start = nullptr;
        char* end = nullptr;
        int busy_blocks = 0;
        int block_size = 0;
        luaM_getpagewalkinfo(page, &start, &end, &busy_blocks, &block_size);
        for (char* position = start; position != end; position += block_size) {
            GCObject* object = (GCObject*)position;
            if (object->gch.tt != LUA_TTHREAD) {
                continue;
            }
            lua_State* candidate = &object->th;
            if (candidate->global != state->global || !candidate->userdata) {
                continue;
            }
            if (*(void**)((uintptr_t)candidate->userdata + 0x40) == script) {
                return candidate;
            }
        }
    }
    return nullptr;
}

}

std::int32_t getsenv(lua_State* L) {
    int type = lua_type(L, 1);
    if (type != LUA_TUSERDATA && type != LUA_TLIGHTUSERDATA) {
        luaL_typeerrorL(L, 1, OBF("Script"));
        return 0;
    }

    void* script = const_cast<void*>(lua_topointer(L, 1));
    lua_State* current = lua_mainthread(L);
    if (!script || !current || !current->global) {
        lua_pushstring(L, OBF("script is not currently running"));
        lua_error(L);
        return 0;
    }

    lua_State* found = find_script_thread(current, script);
    bool foreign = false;
    if (!found && roblox_manager.scriptctx) {
        uintptr_t context = (uintptr_t)roblox_manager.scriptctx;
        for (size_t state_index = 0; state_index < 2 && !found; ++state_index) {
            uintptr_t state_entry = context + 0x130 + 0x18 + state_index * 0x210;
            uintptr_t handle = state_entry + 0x1e8;
            uint64_t low = (uint32_t)handle - *(uint32_t*)handle;
            uint64_t high = (uint32_t)(handle >> 32) - *(uint32_t*)(handle + 4);
            lua_State* alternate = (lua_State*)(low | (high << 32));
            if (!alternate || !alternate->global || alternate->global == current->global) {
                continue;
            }
            if (find_script_thread(alternate, script)) {
                foreign = true;
            }
        }
    }

    if (foreign) {
        lua_pushnil(L);
        return 1;
    }
    if (!found) {
        lua_pushstring(L, OBF("script is not currently running"));
        lua_error(L);
        return 0;
    }

    lua_pushvalue(found, LUA_GLOBALSINDEX);
    lua_xmove(found, L, 1);
    return 1;
}

std::int32_t getrenv(lua_State* L) {
    lua_State* main = lua_mainthread(L);
    if (!main) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushvalue(main, LUA_GLOBALSINDEX);
    lua_xmove(main, L, 1);
    return 1;
}

std::int32_t getgenv(lua_State* L) {
    lua_State* main = lua_mainthread(L);
    if (!main) {
        lua_pushnil(L);
        return 1;
    }

    lua_rawgetp(main, LUA_REGISTRYINDEX, &genv_key);
    if (lua_istable(main, -1)) {
        lua_xmove(main, L, 1);
        return 1;
    }

    lua_pop(main, 1);
    lua_newtable(main);
    lua_pushvalue(main, -1);
    lua_rawsetp(main, LUA_REGISTRYINDEX, &genv_key);
    lua_xmove(main, L, 1);
    return 1;
}

std::int32_t loadstring(lua_State* L) {
    return function_mgr.load_string((void*)L);
}

std::int32_t clonefunction(lua_State* L) {
    if (lua_type(L, 1) != LUA_TFUNCTION) {
        luaL_typeerrorL(L, 1, OBF("function"));
        return 0;
    }

    if (!lua_iscfunction(L, 1)) {
        lua_clonefunction(L, 1);
        return 1;
    }

    Closure* original = reinterpret_cast<Closure*>(const_cast<void*>(lua_topointer(L, 1)));
    if (!original || !original->c.f) {
        lua_pushstring(L, OBF("invalid c closure"));
        lua_error(L);
        return 0;
    }

    int upvalue_count = original->nupvalues;
    for (int index = 1; index <= upvalue_count; ++index) {
        if (!lua_getupvalue(L, 1, index)) {
            lua_pushstring(L, OBF("unable to clone c closure upvalues"));
            lua_error(L);
            return 0;
        }
    }

    lua_pushcclosurek(L, original->c.f, nullptr, upvalue_count, original->c.cont);
    return 1;
}

std::int32_t run_on_actor(lua_State* L) {
    size_t source_size = 0;
    const char* source = luaL_checklstring(L, 2, &source_size);
    if (lua_type(L, 1) != LUA_TUSERDATA && lua_type(L, 1) != LUA_TLIGHTUSERDATA) {
        luaL_typeerrorL(L, 1, OBF("Actor"));
        return 0;
    }

    lua_State* actor_state = actor_global_state(L);
    if (!actor_state || !actor_state->global) {
        lua_pushstring(L, OBF("actor global state is unavailable"));
        lua_error(L);
        return 0;
    }

    script_context* context = roblox_manager.scriptctx;
    if (!context) {
        context = *(script_context**)((uintptr_t)actor_state->global + 0x4e0);
    }
    if (!context) {
        lua_pushstring(L, OBF("actor execution context is unavailable"));
        lua_error(L);
        return 0;
    }

    int status = roblox_manager.execute_script(source,
                                                source_size,
                                                OBF("=run_on_actor"),
                                                actor_state,
                                                context,
                                                execution_actor);
    if (status != 0) {
        lua_pushfstring(L, OBF("actor execution failed with status %d"), status);
        lua_error(L);
        return 0;
    }

    return 0;
}

void on_game_loaded(void* sender, void* data) {
    static std::atomic<uint32_t> fire_count{0};
    uint32_t current_fire = fire_count.fetch_add(1, std::memory_order_relaxed) + 1;
    if (current_fire != 2) {
        return;
    }

    static auto startup_script = OBF(R"AURORA(local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

function identifyexecutor()
    return "Aurora", "1.0.0"
end

local function getThreadIdentity()
    if getthreadidentity then
        return getthreadidentity()
    elseif getidentity then
        return getidentity()
    end
    return "Unknown"
end

local MobileBlox = Instance.new("ScreenGui")
MobileBlox.Name = "MobileBlox"
MobileBlox.Parent = CoreGui
MobileBlox.IgnoreGuiInset = true
MobileBlox.DisplayOrder = 999999

local UIScale = Instance.new("UIScale", MobileBlox)
UIScale.Scale = math.clamp(workspace.CurrentCamera.ViewportSize.X / 1920, 0.6, 1.2)

local function corner(obj)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0,8)
    c.Parent = obj
end

local Main = Instance.new("Frame", MobileBlox)
Main.BackgroundColor3 = Color3.fromRGB(50,50,50)
Main.Position = UDim2.new(0.318,0,0.198,0)
Main.Size = UDim2.new(0,492,0,282)
corner(Main)

local Title = Instance.new("TextLabel", Main)
Title.Size = UDim2.new(1,0,0,25)
Title.BackgroundTransparency = 1
Title.Text = "Aurora"
Title.TextColor3 = Color3.fromRGB(255,255,255)
Title.TextScaled = true

local TextBox = Instance.new("TextBox", Main)
TextBox.BackgroundColor3 = Color3.fromRGB(33,33,33)
TextBox.Position = UDim2.new(0.037,0,0.12,0)
TextBox.Size = UDim2.new(0,450,0,180)
TextBox.ClearTextOnFocus = false
TextBox.MultiLine = true
TextBox.TextWrapped = true
TextBox.Text = ""
TextBox.PlaceholderText = "-- enter your script here..."
TextBox.Font = Enum.Font.Ubuntu
TextBox.TextColor3 = Color3.fromRGB(255,255,255)
TextBox.PlaceholderColor3 = Color3.fromRGB(150,150,150)
TextBox.TextSize = 14
TextBox.TextXAlignment = Enum.TextXAlignment.Left
TextBox.TextYAlignment = Enum.TextYAlignment.Top
corner(TextBox)

local Execute = Instance.new("TextButton", Main)
Execute.Text = "Execute"
Execute.Size = UDim2.new(0,200,0,50)
Execute.Position = UDim2.new(0.036,0,0.82,0)
Execute.BackgroundColor3 = Color3.fromRGB(63,190,93)
Execute.TextColor3 = Color3.fromRGB(255,255,255)
Execute.TextScaled = true
corner(Execute)

local Clear = Instance.new("TextButton", Main)
Clear.Text = "Clear"
Clear.Size = UDim2.new(0,200,0,50)
Clear.Position = UDim2.new(0.544,0,0.82,0)
Clear.BackgroundColor3 = Color3.fromRGB(144,0,0)
Clear.TextColor3 = Color3.fromRGB(255,255,255)
Clear.TextScaled = true
corner(Clear)

local Toggle = Instance.new("TextButton", MobileBlox)
Toggle.Size = UDim2.new(0,60,0,60)
Toggle.Position = UDim2.new(0,20,0.5,0)
Toggle.BackgroundColor3 = Color3.fromRGB(40,40,40)
Toggle.Text = "AR"
Toggle.TextColor3 = Color3.fromRGB(255,255,255)
Toggle.TextScaled = true
corner(Toggle)

local function notify(text)
    local Notif = Instance.new("TextLabel", MobileBlox)
    Notif.Size = UDim2.new(0,250,0,50)
    Notif.Position = UDim2.new(1,300,1,-60)
    Notif.BackgroundColor3 = Color3.fromRGB(30,30,30)
    Notif.TextColor3 = Color3.fromRGB(255,255,255)
    Notif.TextScaled = true
    Notif.Text = text
    corner(Notif)

    TweenService:Create(Notif, TweenInfo.new(0.25), {
        Position = UDim2.new(1,-260,1,-60)
    }):Play()

    task.delay(3, function()
        TweenService:Create(Notif, TweenInfo.new(0.25), {
            Position = UDim2.new(1,300,1,-60)
        }):Play()
        task.wait(0.25)
        Notif:Destroy()
    end)
end

local function dragify(frame)
    local dragging = false
    local dragInput, dragStart, startPos

    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

dragify(Main)
dragify(Toggle)

local opened = true

Toggle.MouseButton1Click:Connect(function()
    opened = not opened
    Main.Visible = opened
end)

Clear.MouseButton1Click:Connect(function()
    TextBox.Text = ""
    notify("Cleared")
end)

Execute.MouseButton1Click:Connect(function()
    local func, err = loadstring(TextBox.Text)
    if not func then
        notify("Compile Error")
        warn(err)
        return
    end

    local success, runtimeErr = pcall(func)

    if success then
        notify("Executed")
    else
        notify("Runtime Error")
        warn(runtimeErr)
    end
end)

local name, ver = identifyexecutor()
print(name, ver)
print("Thread:", getThreadIdentity())
notify("Aurora Loaded")
)AURORA");
    const char* source = startup_script;
    int status = roblox_manager.execute_script(source,
                                                strlen(source),
                                                OBF("=ongameloaded"),
                                                nullptr,
                                                nullptr,
                                                execution_normal);
    if (status != 0) {
        utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("onGameLoaded execution failed status=%d sender=%p data=%p"), status, sender, data] UTF8String]);
    }
}

}
