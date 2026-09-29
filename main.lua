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
            pc = callstack[#callstack]
            table.remove(callstack,#callstack)
        elseif op == 0x00E0 then
            -- IMPLEMENT: clear screen
        else
            -- IMPLEMENT: call machine code routine silly shit
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
        register[x+1]=register[x+1]+nn
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
            register[x+1] = register[x+1] ^ register[y+1]

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
            register[x+1] = register[y+1] - register[x+1]
            -- important: add VF underflow behavior here

        elseif c == 0xE then
            register[x+1] = register[x+1] << 1
            -- important: fuck

        end
    end,

    [9] = function (op)
        local x = (op & 0x0F00) >> 8
        local y = (op & 0x00F0) >> 4
        if register[x+1] ~= register[y+1] then
            pc = pc + 2
        end
    end,

    [0xA] = function (op)
        local nnn = (op & 0x0FFF)
        pc = nnn
    end,

    [0xB] = function (op)
        local nnn = (op & 0x0FFF)
        pointer = nnn + register[1]
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
            -- IMPLEMENT
        elseif c == 0x55 then
            -- IMPLEMENT
        elseif c == 0x65 then
            -- IMPLEMENT
        end
    end
}

while true do
    local op = (program[pc + 1] << 8) + program[pc + 2]
    opcodes[(op & 0xF000) >> 12](op)
    pc = pc+2
end