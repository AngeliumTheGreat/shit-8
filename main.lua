local sys = require "system"
--[[
io.write("\27[2J") -- clear screen
io.write("\27[H")  -- cursor home
io.write("\27[?25l") -- hide cursor
io.flush()
]]

-- platform
local platform = "windows" 

-- placeholder program, add file loading of program in here later
local program = {0x06, 0xD0, 0x08, 0x10, 0xFF, 0x00, 0x20, 0x49, 0x4F, 0x75, 0x7F, 0x7E, 0x4A}
program[0] = 0xA0
for i=0,4095 do
    program[i] = program[i] or 0
end

-- load file 
if (#arg>0) and not (arg[1]=="--test") then
    local file = assert(io.open(arg[#arg], "rb"))
    local rom = file:read("*a")
    file:close()

    for i = 1, 0x200 do
       program[i - 1] = 0
    end

    for i = 1, math.min(#rom, 0xDFF) do
        program[i - 1 + 0x200] = string.byte(rom, i)
    end
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

local settings = {
    frequency = function(v) tick_length = 1 / v end,
    keys = function(v)
        keycodes = {}
        for i=1, 16 do
           keycodes[v:sub(i, i)] = i - 1
        end
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
        io.stdin:read "*a"
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

        elseif c == 2 then
            register[x] = register[x] & register[y]

        elseif c == 3 then
            register[x] = register[x] ~ register[y]

        elseif c == 4 then
            if register[x] + register[y] > 0xFF then 
                register[VF]=1
                else register[VF]=0
            end
            register[x] = (register[x] + register[y]) % 256

        elseif c == 5 then
            if register[x] - register[y] < 0 then
                register[VF]=0
                else register[VF]=1
            end
            register[x] = (register[x] - register[y]) % 256

        elseif c == 6 then
            register[VF] = register[x] & 0x1
            register[x] = register[x] >> 1

        elseif c == 7 then
            if (register[y] - register[x] < 0) then
                register[VF]=0
                else register[VF]=1
            end
            register[x] = (register[y] - register[x]) % 256

        elseif c == 0xE then
            register[VF] = (register[x] & 0x80) >> 7
            register[x] = (register[x] << 1) & 0xFF

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
                local px = (x + j) % 64
                local py = (y + i) % 32

                local bit = (program[pointer + i] >> (7 - j)) & 1

                if screen[px][py] == 1 and bit == 1 then
                    register[0xF] = 1
                end

                screen[px][py] = screen[px][py] ~ bit
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
                if platform=="linux" then io.stdin:read "*a" end
                local key = sys.readansi(math.huge)
                if keycodes[key] then
                    register[x] = keycodes[key]
                    if platform=="linux" then io.stdin:read "*a" end
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

        elseif c == 0x65 then
            for i=0,x do
                register[i]=program[pointer+i]
            end

        else error("invalid FXNN instruction")

        end
    end
}

-- tests if only arg is --test
if #arg == 1 and arg[1] == "--test" then
    local function run(op) return opcodes[(op & 0xF000) >> 12](op) end

    run(0xF018)

    -- 1NNN
    pc = 0  -- set pc
    run(0x1420)
    assert(pc == 0x420)

    -- 3XNN, 4XNN, 5XY0, 9XY0
    do
        pc = 4
        register[3] = 0x33
        run(0x3333)     -- increment pc if V3 is 0x33. should
        assert(pc == 6 and register[3] == 0x33)
        run(0x3320)     -- increment pc if V3 is 0x20. shouldn't
        assert(pc == 6)
        run(0x4333)     -- increment pc if V3 isn't 0x33. shouldn't
        assert(pc == 6 and register[3] == 0x33)
        run(0x4320)     -- increment pc if V3 isn't 0x20. should
        assert(pc == 8)
        register[7] = 0xF
        register[8] = 0xF
        run(0x5370)     -- increment pc if V3 and V7 are equal. shouldn't
        assert(pc == 8 and register[7] == 0xF)
        run(0x5870)     -- increment pc if V8 and V7 are equal. should
        assert(pc == 10)
        run(0x9870)     -- increment pc if V8 and V7 are unequal. shouldn't
        assert(pc == 10)
        run(0x9830)     -- increment pc if V8 and V3 are unequal. should
        assert(pc == 12)
    end

    -- 00EE, 2NNN
    do
        pc = 0x200
        run(0x2300)     -- call subroutine. should change pc and add to the callstack
        assert(pc == 0x300)
        local callstack_size = #callstack
        assert(callstack[#callstack] == 0x200)
        run(0x00EE)     -- return from subroutine. should change pc and remove from the callstack
        assert(pc == 0x200)
        assert(#callstack == callstack_size - 1)
    end

    -- 6XNN
    register[1] = 0x40  -- set V1 to 0x50
    run(0x6150)
    assert(register[1] == 0x50)

    -- ANNN
    run(0xA123)     -- set I to 0x123
    assert(pointer == 0x123)
    run(0xA321)     -- set I to 0x321
    assert(pointer == 0x321)

    -- BNNN
    pc = 0x12
    register[0] = 0x4
    run(0xB200)     -- set pc to 0x200 + V0
    assert(pc == 0x204)

    -- CXNN
    for i=1, 100 do
        run(0xC40F) -- set V4 to a random number & 0xF0
        assert(register[4] & 0xF0 == 0)
    end

    -- 7XNN
    register[2] = 0xD0
    run(0x7208) -- add 0x08 to V2
    assert(register[2] == 0xD8)
    run(0x72FF) -- add 0xFF to V2
    assert(register[2] <= 0xFF)

    -- 8XY0, 8XY1, 8XY2, 8XY3, 8XY4, 8XY5, 8XY6, 8XY7, 8XYE
    do
        register[0] = 0x0; register[1] = 0xFF
        run(0x8010)
        assert(register[0] == 0xFF)
        register[0] = 0xF0; register[1] = 0x0F
        run(0x8011)
        assert(register[0] == 0xFF)
        run(0x8012)
        assert(register[0] == 0x0F)
        register[1] = 0x88
        run(0x8013)
        assert(register[0] == 0x87)
    end

    -- FX0A
    print "for test, press the 3 key"
    register[3] = 0x0
    run(0xF30A)
    assert(register[3] == keycodes["3"])

    -- FX07 and FX15
    register[3] = 120; register[4] = 0
    run(0xF315) -- set timer to 120
    run(0xF407)
    assert(register[4] == 120)  -- immediately, timer is 120
    sys.sleep(1)
    run(0xF407)
    assert(register[4] == 60)   -- wait 1s, timer is 60
    sys.sleep(0.001)
    run(0xF407)
    assert(register[4] == 60)   -- wait 1ms, timer is still 60
    sys.sleep(20/60)
    run(0xF407)
    assert(register[4] == 40)   -- wait 333ms, timer is 40
    sys.sleep(1)
    run(0xF407)
    assert(register[4] == 0)    -- wait 1s, timer is 0 (never negative)

    print "all tests good!"
    os.exit()
end

while true do
    -- get_pressed()
    local op = (program[pc] << 8) + program[pc + 1]
    pc = pc + 2
    -- print(string.format("PC=%04X OP=%04X", pc - 2, op))
    opcodes[(op & 0xF000) >> 12](op)
    sys.sleep(tick_length)
end
