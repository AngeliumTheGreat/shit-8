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

-- opcodes
local opcodes = {
    [6] = function(op)
      local x = (op & 0x0F00)>>8
      local nn = (op & 0x00FF)
      register[x+1]=nn
      print(register[x+1])
    end,
}

while true do
    local op = (program[pc + 1] << 8) + program[pc + 2]
    opcodes[(op & 0xF000) >> 12](op)
    pc = pc+2
end