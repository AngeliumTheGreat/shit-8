-- placeholder program, add file loading of program in here later
local program = {0x61,0x23}
for i=1,4096 do
    program[i]=(program[i] or 0)
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
        pc = pc + 2
        table.insert(callstack, pc)
        pc = nnn
    end,

    [3] = function (op)
        local x = (op & 0x0F00) >> 8
        local nn = (op & 0x00FF)
        if register[x+1] == nn then
            pc = pc + 2
        end
    end,

    [4] = function (op)
        local x = (op & 0x0F00) >> 8
        local nn = (op & 0x00FF)
        if register[x+1] ~= nn then
            pc = pc + 2
        end
    end,

    [5] = function (op)
        if (op & 0x000F) ~= 0 then
            return
        end
        local x = (op & 0x0F00) >> 8
        local y = (op & 0x00F0) >> 4
        if register[x+1] == register[y+1] then
            pc = pc + 2
        end
    end,

    [6] = function(op)
        local x = (op & 0x0F00) >> 8
        local nn = (op & 0x00FF)
        register[x+1]=nn
    end,

    [7] = function (op)
        local x = (op & 0x0F00) >> 8
        local nn = (op & 0x00FF)
        register[x+1]= (register[x+1]+nn) & 0xFF
    end,

    [8] = function (op)
        local x = (op & 0x0F00) >> 8
        local y = (op & 0x00F0) >> 4
        local c = (op & 0x000F)

        if c == 0 then
            register[x+1] = register[y+1]

        elseif c == 1 then
            register[x+1] = register[x+1] | register[y+1]

        elseif c == 2 then
            register[x+1] = register[x+1] & register[y+1]

        elseif c == 3 then
            register[x+1] = register[x+1] ~ register[y+1]

        elseif c == 4 then
            if register[x+1] + register[y+1] > 0xFF then 
                register[16]=1
                else register[16]=0
            end
            register[x+1] = (register[x+1] + register[y+1]) % 256

        elseif c == 5 then
            if register[x+1] - register[y+1] < 0 then 
                register[16]=0
                else register[16]=1
            end
            register[x+1] = (register[x+1] - register[y+1]) % 256

        elseif c == 6 then
            register[16] = register[x+1] & 0x1
            register[x+1] = register[x+1] >> 1

        elseif c == 7 then
            if (register[y+1] - register[x+1] < 0) then
                register[16]=0
                else register[16]=1
            end
            register[x+1] = (register[y+1] - register[x+1]) % 256
            
        elseif c == 0xE then
            register[16] = (register[x+1] & 0x80) >> 7
            register[x+1] = (register[x+1] << 1) & 0xFF

        end
    end,

    [9] = function (op)
        if (op & 0x000F) ~= 0 then
            return
        end
        local x = (op & 0x0F00) >> 8
        local y = (op & 0x00F0) >> 4
        if register[x+1] ~= register[y+1] then
            pc = pc + 2
        end
    end,

    [0xA] = function (op)
        local nnn = (op & 0x0FFF)
        pointer = nnn
    end,

    [0xB] = function (op)
        local nnn = (op & 0x0FFF)
        pc = nnn + register[1]
    end,

    [0xC] = function (op)
        local x = (op & 0x0F00) >> 8
        local nn = (op & 0x00FF)
        register[x+1] = math.random(0, 255) & nn
    end,

    [0xF] = function (op)
        local x = (op & 0x0F00) >> 8
        local c = (op & 0x00FF)
        if c == 0x07 then
            register[x+1] = delay_timer

        elseif c == 0x0A then
            -- IMPLEMENT

        elseif c == 0x15 then
            delay_timer = register[x+1]

        elseif c == 0x18 then
            sound_timer = register[x+1]

        elseif c == 0x1E then
            pointer = pointer + register[x+1]

        elseif c == 0x29 then
            -- IMPLEMENT

        elseif c == 0x33 then
            program[pointer] = math.floor(register[x+1] / 100)
            program[pointer+1] = math.floor((register[x+1] / 10) % 10)
            program[pointer+2] = register[x+1] % 10

        elseif c == 0x55 then
            for i=0,x do
                program[pointer+i]=register[i+1]
            end

        elseif c == 0x65 then
            for i=0,x do
                register[i+1]=program[pointer+i]
            end

        end
    end
}

-- tests if only arg is --test
if #arg == 1 and arg[1] == "--test" then
    local function run(op) return opcodes[(op & 0xF000) >> 12](op) end

    -- 1NNN
    pc = 0
    run(0x1420)
    assert(pc == 0x420)

    -- 3XNN, 4XNN, 5XY0, 9XY0
    do
        pc = 4
        register[4] = 0x33
        run(0x3333)
        assert(pc == 6 and register[4] == 0x33)
        run(0x3320)
        assert(pc == 6)
        run(0x4333)
        assert(pc == 6 and register[4] == 0x33)
        run(0x4320)
        assert(pc == 8)
        register[8] = 0xF
        register[9] = 0xF
        run(0x5370)
        assert(pc == 8 and register[8] == 0xF and register[9] == 0xF)
        run(0x5870)
        assert(pc == 10)
        run(0x9870)
        assert(pc == 10)
        run(0x9830)
        assert(pc == 12)
    end

    -- 00EE, 2NNN
    do
        pc = 0x200
        run(0x2300)
        assert(pc == 0x300)
        local callstack_size = #callstack
        assert(callstack[#callstack] == 0x202)
        run(0x00EE)
        assert(pc == 0x202)
        assert(#callstack == callstack_size - 1)
    end

    -- 6XNN
    register[2] = 0x40
    run(0x6150)
    assert(register[2] == 0x50)

    -- ANNN
    run(0xA123)
    assert(pointer == 0x123)
    run(0xA321)
    assert(pointer == 0x321)

    -- BNNN
    pc = 0x12
    register[1] = 0x4
    run(0xB200)
    assert(pc == 0x204)

    -- CXNN
    for i=1, 100 do
        run(0xC40F)
        assert(register[5] & 0xF0 == 0)
    end

    -- 7XNN
    register[3] = 0xD0
    run(0x7208)
    assert(register[3] == 0xD8)
    run(0x72FF)
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
