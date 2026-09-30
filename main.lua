-- placeholder program, add file loading of program in here later
local memory = {0x61,0x23}
for i=1,4096 do
    memory[i]=(memory[i] or 0)
end

-- variable registers
local register = {}
for i=1,16 do
    register[i]=(register[i] or 0)
end

-- instruction pointer and program counter
local pointer = 0
local pc = 0

-- callstack
local callstack = {}

-- timers
local delay_timer = 0
local sound_timer = 0

-- vf is funky
local VF = 0xF

-- helper functions for accessing registers and memory
local function get_reg(n)
    return register[n + 1]
end

local function set_reg(n, v)
    assert(0 <= v and v <= 0xFF, "register value out of range")
    register[n + 1] = v
end

local function get_mem(n)
    return memory[n + 1]
end

local function set_mem(n, v)
    assert(0 <= v and v <= 0xFF, "memory value out of range")
    memory[n + 1] = v
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
            -- IMPLEMENT: clear screen
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
        if get_reg(x) == nn then
            pc = pc + 2
        end
    end,

    [4] = function (op)
        local x = (op & 0x0F00) >> 8
        local nn = (op & 0x00FF)
        if get_reg(x) ~= nn then
            pc = pc + 2
        end
    end,

    [5] = function (op)
        if (op & 0x000F) ~= 0 then
            error("invalid 5XY0 instruction")
        end
        local x = (op & 0x0F00) >> 8
        local y = (op & 0x00F0) >> 4
        if get_reg(x) == get_reg(y) then
            pc = pc + 2
        end
    end,

    [6] = function(op)
        local x = (op & 0x0F00) >> 8
        local nn = (op & 0x00FF)
        set_reg(x, nn)
    end,

    [7] = function (op)
        local x = (op & 0x0F00) >> 8
        local nn = (op & 0x00FF)
        set_reg(x, (get_reg(x)+nn) & 0xFF)
    end,

    [8] = function (op)
        local x = (op & 0x0F00) >> 8
        local y = (op & 0x00F0) >> 4
        local c = (op & 0x000F)

        if c == 0 then
            set_reg(x, get_reg(y))

        elseif c == 1 then
            set_reg(x, get_reg(x) | get_reg(y))

        elseif c == 2 then
            set_reg(x, get_reg(x) & get_reg(y))

        elseif c == 3 then
            set_reg(x, get_reg(x) ~ get_reg(y))

        elseif c == 4 then
            if get_reg(x) + get_reg(y) > 0xFF then
                set_reg(VF, 0x1)
                else set_reg(VF, 0x0)
            end
            set_reg(x, (get_reg(x) + get_reg(y)) % 256)

        elseif c == 5 then
            if get_reg(x) - get_reg(y) < 0 then
                set_reg(VF, 0x0)
                else set_reg(VF, 0x1)
            end
            set_reg(x, (get_reg(x) - get_reg(y)) % 256)

        elseif c == 6 then
            set_reg(VF, get_reg(x) & 0x1)
            set_reg(x, get_reg(x) >> 1)

        elseif c == 7 then
            if (get_reg(y) - get_reg(x) < 0) then
                set_reg(VF, 0x0)
                else set_reg(VF, 0x1)
            end
            set_reg(x, (get_reg(y) - get_reg(x)) % 256)

        elseif c == 0xE then
            set_reg(VF, (get_reg(x) & 0x80) >> 7)
            set_reg(x, (get_reg(x) << 1) & 0xFF)

        else error("invalid 8XYN instruction")

        end
    end,

    [9] = function (op)
        if (op & 0x000F) ~= 0 then
            error("invalid 9XY0 instruction")
        end
        local x = (op & 0x0F00) >> 8
        local y = (op & 0x00F0) >> 4
        if get_reg(x) ~= get_reg(y) then
            pc = pc + 2
        end
    end,

    [0xA] = function (op)
        local nnn = (op & 0x0FFF)
        pointer = nnn
    end,

    [0xB] = function (op)
        local nnn = (op & 0x0FFF)
        pc = nnn + get_reg(0)
    end,

    [0xC] = function (op)
        local x = (op & 0x0F00) >> 8
        local nn = (op & 0x00FF)
        set_reg(x, math.random(0, 255) & nn)
    end,

    [0xD] = function (op)
        local x = (op & 0x0F00) >> 8
        local y = (op & 0x00F0) >> 4
        local n = (op & 0x000F)
        -- IMPLEMENT: draw sprite
    end,

    [0xE] = function (op)
        local x = (op & 0x0F00) >> 8
        local c = (op & 0x00FF)
        if c == 0x9E then
            -- IMPLEMENT: key press stuff

        elseif c == 0xA1 then
            -- IMPLEMENT: key press stuff
        
        else error("invalid EXNN instruction") end
    end,

    [0xF] = function (op)
        local x = (op & 0x0F00) >> 8
        local c = (op & 0x00FF)
        if c == 0x07 then
            set_reg(x, delay_timer)

        elseif c == 0x0A then
            -- IMPLEMENT: getkey

        elseif c == 0x15 then
            delay_timer = get_reg(x)

        elseif c == 0x18 then
            sound_timer = get_reg(x)

        elseif c == 0x1E then
            pointer = pointer + get_reg(x)

        elseif c == 0x29 then
            -- IMPLEMENT: sprite char pointer thing

        elseif c == 0x33 then
            set_mem(pointer, math.floor(get_reg(x) / 100) % 10)
            set_mem(pointer+1, math.floor((get_reg(x) / 10) % 10))
            set_mem(pointer+2, get_reg(x) % 10)

        elseif c == 0x55 then
            for i=0,x do
                set_mem(pointer+i, get_reg(i))
            end

        elseif c == 0x65 then
            for i=0,x do
                set_reg(i, get_mem(pointer + i))
            end

        else error("invalid FXNN instruction")

        end
    end
}

-- tests if only arg is --test
if #arg == 1 and arg[1] == "--test" then
    local function run(op) return opcodes[(op & 0xF000) >> 12](op) end

    -- 1NNN
    pc = 0  -- set pc
    run(0x1420)
    assert(pc == 0x420)

    -- 3XNN, 4XNN, 5XY0, 9XY0
    do
        pc = 4
        register[4] = 0x33
        run(0x3333)     -- increment pc if V3 is 0x33. should
        assert(pc == 6 and register[4] == 0x33)
        run(0x3320)     -- increment pc if V3 is 0x20. shouldn't
        assert(pc == 6)
        run(0x4333)     -- increment pc if V3 isn't 0x33. shouldn't
        assert(pc == 6 and register[4] == 0x33)
        run(0x4320)     -- increment pc if V3 isn't 0x20. should
        assert(pc == 8)
        register[8] = 0xF
        register[9] = 0xF
        run(0x5370)     -- increment pc if V3 and V7 are equal. shouldn't
        assert(pc == 8 and register[8] == 0xF)
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
    register[2] = 0x40  -- set V1 to 0x50
    run(0x6150)
    assert(register[2] == 0x50)

    -- ANNN
    run(0xA123)     -- set I to 0x123
    assert(pointer == 0x123)
    run(0xA321)     -- set I to 0x321
    assert(pointer == 0x321)

    -- BNNN
    pc = 0x12
    register[1] = 0x4
    run(0xB200)     -- set pc to 0x200 + V0
    assert(pc == 0x204)

    -- CXNN
    for i=1, 100 do
        run(0xC40F) -- set V4 to a random number & 0xF0
        assert(register[5] & 0xF0 == 0)
    end

    -- 7XNN
    register[3] = 0xD0
    run(0x7208) -- add 0x08 to V2
    assert(register[3] == 0xD8)
    run(0x72FF) -- add 0xFF to V2
    assert(register[3] <= 0xFF)

    -- 8XY0, 8XY1, 8XY2, 8XY3, 8XY4, 8XY5, 8XY6, 8XY7, 8XYE
    do
        register[1] = 0x0; register[2] = 0xFF
        run(0x8010)
        assert(register[1] == 0xFF)
        register[1] = 0xF0; register[2] = 0x0F
        run(0x8011)
        assert(register[1] == 0xFF)
        run(0x8012)
        assert(register[1] == 0x0F)
        register[2] = 0x88
        run(0x8013)
        assert(register[1] == 0x87)
    end

    print "all tests good!"
    os.exit()
end

while true do
    local op = (program[pc + 1] << 8) + program[pc + 2]
    pc = pc + 2
    opcodes[(op & 0xF000) >> 12](op)
end
