#pragma once

#include "../../obfuscation.hpp"

namespace managers::core {

inline const char* startup_script() {
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
    return startup_script;
}

}
