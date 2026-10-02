--[[
    SPDX-FileCopyrightText: NONE
    SPDX-License-Identifier: CC0-1.0
]]

local sys = require "system"
io.write("\27[?25l") -- hide cursor

-- platform
local platform = package.config:sub(1, 1) == "\\" and "windows" or "linux"
if platform == "windows" then
    os.execute("chcp 65001 > nul 2>&1")
end

-- the program array
local program = {}

-- load file 
if (#arg>0) and arg[#arg]:sub(1, 2) ~= "--" then
    local file = assert(io.open(arg[#arg], "rb"))
    local rom = file:read("*a")
    file:close()

    for i = 1, 0x200 do
       program[i - 1] = 0
    end

    for i = 1, math.min(#rom, 0xE00) do
        program[i - 1 + 0x200] = string.byte(rom, i)
    end

else print("no program specified") os.exit()

end

-- start of font sprites
local font_start = 0x000

-- variable registers
local register = {}
for i=0,0xF do
    register[i]=(register[i] or 0)
end

-- instruction pointer and program counter
local pointer = 0
local pc = 0x200

-- callstack
local callstack = {}

-- timers
local delay_timer = 0
local delay_timer_set_time = 0
local sound_timer = 0

-- vf is funky
local VF = 0xF

-- temp carry flag
local carry = 0

-- screen
local screen = {}
for x = 0, 63 do
    screen[x] = {}
    for y = 0, 31 do
        screen[x][y] = 0
    end
end

-- array of keys for 0 to F
local keycodes = {
    ["0"] = 0, ["1"] = 1, ["2"] = 2, ["3"] = 3,
    ["4"] = 4, ["5"] = 5, ["6"] = 6, ["7"] = 7,
    ["8"] = 8, ["9"] = 9, ["a"] = 10, ["b"] = 11,
    ["c"] = 12, ["d"] = 13, ["e"] = 14, ["f"] = 15,
}

local tick_length = 1 / 800
local key_interval = 30

local settings = {
    frequency = function(v) tick_length = 1 / v end,
    keys = function(v)
        keycodes = {}
        for i=1, 16 do
           keycodes[v:sub(i, i)] = i - 1
        end
    end,
    ["key-interval"] = function(v)
        key_interval = math.ceil(tonumber(v) or 30)
    end,
    help = function()
        print [[
usage: shit-8 [options] <file>

options are of form --OPTION or --OPTION=VALUE

options:
--help              display this help and close the program
--frequency=X       run the vm at X Hz
--key-interval=X    poll for pressed keys every X clock cycles
--keys=XXXX         use the 16 chars XXXX as the keys 0 to F
]]
        os.exit()
    end,
}

setmetatable(settings, { __index = function() return function() end end })

-- get config from args
for i, v in ipairs(arg) do
    if v:sub(1, 2) == "--" then
        settings[select(3, v:find("%-%-([%w-]+)"))](select(3, v:find("%-%-%w+=(.*)$")))
    end
end

-- setup Windows console to handle ANSI processing
local of_in = sys.getconsoleflags(io.stdin)
local of_out = sys.getconsoleflags(io.stdout)
sys.setconsoleflags(io.stdout, sys.getconsoleflags(io.stdout) + sys.COF_VIRTUAL_TERMINAL_PROCESSING)
sys.setconsoleflags(io.stdin, sys.getconsoleflags(io.stdin) + sys.CIF_VIRTUAL_TERMINAL_INPUT)

-- setup Posix terminal to use non-blocking mode, and disable line-mode
local of_attr = sys.tcgetattr(io.stdin)
local of_block = sys.getnonblock(io.stdin)
sys.setnonblock(io.stdin, true)
sys.tcsetattr(io.stdin, sys.TCSANOW, {
    lflag = of_attr.lflag - sys.L_ICANON - sys.L_ECHO, -- disable canonical mode and echo
})

local key_pressed
local get_pressed = coroutine.wrap(function()
    while true do
        local key = sys.readansi(0)
        key_pressed = keycodes[key]
        if platform=="linux" then local _ = io.stdin:read "*a" end
        coroutine.yield()
    end
end)

local function draw_screen()
    io.write("\27[H") -- cursor to top-left

    local output = {}

    for y = 0, 31 do
        local row = {}

        for x = 0, 63 do
            if screen[x][y] == 1 then
                row[#row + 1] = "██"
            else
                row[#row + 1] = "  "
            end
        end

        output[#output + 1] = table.concat(row)
    end

    io.write(table.concat(output, "\n"))
    io.flush()
end

-- opcodes
local opcodes = {
    [0] = function (op)
        if op == 0x00EE then
            if #callstack == 0 then
                error("stack underflow")
            end
            pc = callstack[#callstack]
            table.remove(callstack,#callstack)
        elseif op == 0x00E0 then
            for x = 0, 63 do
                for y = 0, 31 do
                    screen[x][y] = 0
                end
            end
        else
            -- literally do nothing; this operation is defunct on modern systems
        end
    end,

    [1] = function (op)
        local nnn = (op & 0x0FFF)
        pc = nnn
    end,

    [2] = function (op)
        local nnn = (op & 0x0FFF)
        table.insert(callstack, pc)
        if #callstack >= 16 then
            error("stack overflow")
        end
        pc = nnn
    end,

    [3] = function (op)
        local x = (op & 0x0F00) >> 8
        local nn = (op & 0x00FF)
        if register[x] == nn then
            pc = pc + 2
        end
    end,

    [4] = function (op)
        local x = (op & 0x0F00) >> 8
        local nn = (op & 0x00FF)
        if register[x] ~= nn then
            pc = pc + 2
        end
    end,

    [5] = function (op)
        if (op & 0x000F) ~= 0 then
            error("invalid 5XY0 instruction")
        end
        local x = (op & 0x0F00) >> 8
        local y = (op & 0x00F0) >> 4
        if register[x] == register[y] then
            pc = pc + 2
        end
    end,

    [6] = function(op)
        local x = (op & 0x0F00) >> 8
        local nn = (op & 0x00FF)
        register[x]=nn
    end,

    [7] = function (op)
        local x = (op & 0x0F00) >> 8
        local nn = (op & 0x00FF)
        register[x]= (register[x]+nn) & 0xFF
    end,

    [8] = function (op)
        local x = (op & 0x0F00) >> 8
        local y = (op & 0x00F0) >> 4
        local c = (op & 0x000F)

        if c == 0 then
            register[x] = register[y]

        elseif c == 1 then
            register[x] = register[x] | register[y]
            register[VF] = 0

        elseif c == 2 then
            register[x] = register[x] & register[y]
            register[VF] = 0

        elseif c == 3 then
            register[x] = register[x] ~ register[y]
            register[VF] = 0

        elseif c == 4 then
            if register[x] + register[y] > 0xFF then 
                carry=1
                else carry=0
            end
            register[x] = (register[x] + register[y]) % 256
            register[VF] = carry

        elseif c == 5 then
            if register[x] - register[y] < 0 then
                carry=0
                else carry=1
            end
            register[x] = (register[x] - register[y]) % 256
            register[VF] = carry

        elseif c == 6 then
            register[x] = register[y]
            carry = register[x] & 0x1
            register[x] = register[x] >> 1
            register[VF] = carry

        elseif c == 7 then
            if (register[y] - register[x] < 0) then
                carry=0
                else carry=1
            end
            register[x] = (register[y] - register[x]) % 256
            register[VF] = carry

        elseif c == 0xE then
            register[x] = register[y]
            carry = (register[x] & 0x80) >> 7
            register[x] = (register[x] << 1) & 0xFF
            register[VF] = carry

        else error("invalid 8XYN instruction")

        end
    end,

    [9] = function (op)
        if (op & 0x000F) ~= 0 then
            error("invalid 9XY0 instruction")
        end
        local x = (op & 0x0F00) >> 8
        local y = (op & 0x00F0) >> 4
        if register[x] ~= register[y] then
            pc = pc + 2
        end
    end,

    [0xA] = function (op)
        local nnn = (op & 0x0FFF)
        pointer = nnn
    end,

    [0xB] = function (op)
        local nnn = (op & 0x0FFF)
        pc = nnn + register[0]
    end,

    [0xC] = function (op)
        local x = (op & 0x0F00) >> 8
        local nn = (op & 0x00FF)
        register[x] = math.random(0, 255) & nn
    end,

    [0xD] = function(op)
        local x = register[(op & 0x0F00) >> 8]
        local y = register[(op & 0x00F0) >> 4]
        local n = op & 0x000F
        register[0xF] = 0

        for i = 0, n - 1 do
            for j = 0, 7 do
                local px = x+j
                local py = y+i
                if x>63 then px = px % 64 end
                if y>31 then py = py % 32 end
                if px>63 then goto SKIP end
                if py>31 then goto SKIP end

                local bit = (program[pointer + i] >> (7 - j)) & 1

                if screen[px][py] == 1 and bit == 1 then
                    register[0xF] = 1
                end

                screen[px][py] = screen[px][py] ~ bit
                ::SKIP::
            end
        end
        draw_screen()
    end,

    [0xE] = function (op)
        local x = (op & 0x0F00) >> 8
        local c = (op & 0x00FF)
        if c == 0x9E then
            if key_pressed == register[x] then
                pc = pc + 2
            end
        elseif c == 0xA1 then
            if key_pressed ~= register[x] then
                pc = pc + 2
            end
        else error("invalid EXNN instruction") end
    end,

    [0xF] = function (op)
        local x = (op & 0x0F00) >> 8
        local c = (op & 0x00FF)
        if c == 0x07 then
            local delta = sys.monotime() - delay_timer_set_time
            register[x] = math.max(delay_timer - math.floor(delta * 60), 0)

        elseif c == 0x0A then
            while true do
                if platform=="linux" then local _ = io.stdin:read "*a" end
                local key = sys.readansi(math.huge)
                if keycodes[key] then
                    register[x] = keycodes[key]
                    if platform=="linux" then local _ = io.stdin:read "*a" end
                    break
                end
            end

        elseif c == 0x15 then
            delay_timer = register[x]
            delay_timer_set_time = sys.monotime()

        elseif c == 0x18 then
            io.write "\a"

        elseif c == 0x1E then
            pointer = pointer + register[x]

        elseif c == 0x29 then
            pointer = font_start + register[x] * 5

        elseif c == 0x33 then
            program[pointer] = math.floor(register[x] / 100) % 10
            program[pointer+1] = math.floor((register[x] / 10) % 10)
            program[pointer+2] = register[x] % 10

        elseif c == 0x55 then
            for i=0,x do
                program[pointer+i]=register[i]
            end
            pointer = pointer+x+1

        elseif c == 0x65 then
            for i=0,x do
                register[i]=program[pointer+i]
            end
            pointer = pointer+x+1

        else error("invalid FXNN instruction")

        end
    end
}

while true do
    get_pressed()
    for i=1, key_interval do
        local op = (program[pc] << 8) + program[pc + 1]
        pc = pc + 2
        -- print(string.format("PC=%04X OP=%04X", pc - 2, op))
        opcodes[(op & 0xF000) >> 12](op)
        sys.sleep(tick_length)
    end
end
