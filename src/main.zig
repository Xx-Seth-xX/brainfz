const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stdin = blk: {
    const aux = std.io.getStdIn();
    break :blk aux;
};

const VirtualMachine = struct {
    const Self = @This();
    const size: comptime_int = 10;
    const MemType = i32;

    memory: [size]MemType,
    ptr: usize,
    program: []const u8,
    iptr: usize,

    // > 	Increment the data pointer by one (to point to the next cell to the right).
    // < 	Decrement the data pointer by one (to point to the next cell to the left).
    // + 	Increment the byte at the data pointer by one.
    // - 	Decrement the byte at the data pointer by one.
    // . 	Output the byte at the data pointer.
    // , 	Accept one byte of input, storing its value in the byte at the data pointer.
    // [ 	If the byte at the data pointer is zero, then instead of moving the instruction pointer forward to the next command, jump it forward to the command after the matching ] command.
    // ] 	If the byte at the data pointer is nonzero, then instead of moving the instruction pointer forward to the next command, jump it back to the command after the matching [ command.[a]

    fn execute_program(self: *Self) !void {
        while (self.iptr < self.program.len) {
            const instr = self.program[self.iptr];
            switch (instr) {
                '+' => self.inc(),
                '-' => self.dec(),
                '>' => try self.incp(),
                '<' => try self.decp(),
                '.' => try self.put(),
                ',' => try self.get(),
                else => {
                    std.log.err("Encountered invalid char {} at index {}", .{ instr, self.iptr });
                    return error.InvalidInstruction;
                },
            }
            self.iptr += 1;
            // std.log.info("Instruction: {c}", .{instr});
            // std.log.info("Memory: {any}, ptr: {}", .{ vm.memory, vm.ptr });
        }
    }
    fn reset(self: *Self) void {
        self.iptr = 0;
        self.ptr = 0;
        self.memory = [_]MemType{0} ** size;
    }
    fn init(program: []const u8) Self {
        return Self{ .memory = [_]MemType{0} ** size, .ptr = 0, .program = program, .iptr = 0 };
    }
    fn inc(self: *Self) void {
        self.memory[self.ptr] += 1;
    }
    fn dec(self: *Self) void {
        self.memory[self.ptr] -= 1;
    }
    fn incp(self: *Self) !void {
        if (self.ptr >= Self.size - 1) {
            return error.OutOfBoundsPtr;
        }
        self.ptr += 1;
    }
    fn decp(self: *Self) !void {
        if (self.ptr <= 0) {
            return error.OutOfBoundsPtr;
        }
        self.ptr -= 1;
    }
    fn put(self: Self) !void {
        const c = self.memory[self.ptr];
        try stdout.print("{}\n", .{c});
    }
    fn get(self: *Self) !void {
        var buff: [1]u8 = undefined;
        if (try stdin.read(&buff) == 0) {
            buff[0] = 0;
        }
        self.memory[self.ptr] = buff[0];
    }
};

pub fn main() !void {
    const program = "+++.,.+.";
    std.log.info("Executing program: \"{s}\"", .{program});
    var vm = VirtualMachine.init(program);
    try vm.execute_program();
    std.log.info("Final state:", .{});
    std.log.info("{}", .{vm});
    try stdout.writeByte('\n');
    return;
}
