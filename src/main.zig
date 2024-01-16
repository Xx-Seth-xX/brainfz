const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn();

const VirtualMachine = struct {
    const Self = @This();
    const size: comptime_int = 1024;
    const MemType = u8;
    const debug: bool = false;
    const operands = "><+-.,[]";
    const Error = error{
        UnmatchedOpeningBracket,
        UnmatchedClosingBracket,
        OutOfBoundsPtr,
        InvalidInstruction,
    };

    fn isOperand(c: u8) bool {
        for (VirtualMachine.operands) |op| {
            if (op == c) return true;
        }
        return false;
    }

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
    fn execute_program(self: *Self) !void {
        while (self.iptr < self.program.len) {
            const instr = self.program[self.iptr];
            if (debug) {
                std.log.info("Memory: {any}, ptr: {}, iptr: {}", .{ self.memory, self.ptr, self.iptr });
                std.log.info("Instruction: {c}", .{instr});
            }
            switch (instr) {
                '+' => self.inc(),
                '-' => self.dec(),
                '>' => try self.incp(),
                '<' => try self.decp(),
                '.' => try self.put(),
                ',' => try self.get(),
                '[' => try self.loopb(),
                ']' => try self.loope(),
                else => {
                    std.log.err("Encountered invalid char {} at index {}", .{ instr, self.iptr });
                    return error.InvalidInstruction;
                },
            }
            self.iptr += 1;
        }
        if (debug) {
            std.log.info("Memory: {any}, ptr: {}", .{ self.memory, self.ptr });
        }
    }
    fn reset(self: *Self) void {
        self.iptr = 0;
        self.ptr = 0;
        self.memory = [_]MemType{0} ** size;
    }
    fn init(program: []const u8) Self {
        return Self{
            .memory = [_]MemType{0} ** size,
            .ptr = 0,
            .program = program,
            .iptr = 0,
        };
    }
    inline fn getAt(self: Self) MemType {
        return self.memory[self.ptr];
    }
    inline fn setAt(self: *Self, v: MemType) void {
        self.memory[self.ptr] = v;
    }
    fn inc(self: *Self) void {
        const val = @addWithOverflow(self.getAt(), 1)[0];
        self.setAt(val);
    }
    fn dec(self: *Self) void {
        const val = @subWithOverflow(self.getAt(), 1)[0];
        self.setAt(val);
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
        _ = try stdout.write(&[_]MemType{c});
        if (debug) try stdout.print("\n");
    }
    fn get(self: *Self) !void {
        var buff: [1]u8 = undefined;
        if (try stdin.read(&buff) == 0) {
            buff[0] = 0;
        }
        self.memory[self.ptr] = @as(MemType, @intCast(buff[0]));
    }

    // [ 	If the byte at the data pointer is zero,
    // then instead of moving the instruction pointer forward to the next command,
    // jump it forward to the command after the matching ] command.
    fn loopb(self: *Self) !void {
        if (self.memory[self.ptr] != 0) {
            return;
        } else if (self.iptr >= self.program.len - 1) {
            return error.UnmatchedOpeningBracket;
        }

        // Tracks nesting
        var counter: usize = 0;
        self.iptr += 1;
        while (self.iptr < self.program.len) : (self.iptr += 1) {
            switch (self.program[self.iptr]) {
                '[' => counter += 1,
                ']' => {
                    if (counter == 0) {
                        return;
                    } else {
                        counter -= 1;
                    }
                },
                else => {},
            }
        }
        return error.UnmatchedOpeningBracket;
    }

    // ] 	If the byte at the data pointer is nonzero, then instead of moving the instruction pointer forward to the next command, jump it back to the command after the matching [ command.[a]
    fn loope(self: *Self) !void {
        if (self.memory[self.ptr] == 0) {
            return;
        } else if (self.iptr == 0) {
            return error.UnmatchedClosingBracket;
        }
        // Tracks nesting
        var counter: usize = 0;
        while (self.iptr > 0) : (self.iptr -= 1) {
            switch (self.program[self.iptr - 1]) {
                ']' => counter += 1,
                '[' => {
                    if (counter == 0) {
                        self.iptr -= 1;
                        return;
                    } else {
                        counter -= 1;
                    }
                },
                else => {},
            }
        }
        return error.UnmatchedClosingBracket;
    }
};

fn loadProgram(alloc: std.mem.Allocator, filename: []const u8) !std.ArrayList(u8) {
    const file = try std.fs.cwd().openFile(filename, .{});
    const text = try file.readToEndAlloc(alloc, 1024 * 1024); // 1MB should be more than enough
    defer alloc.free(text);
    const program = try parseProgram(alloc, text);
    return program;
}

fn parseProgram(alloc: std.mem.Allocator, text: []const u8) !std.ArrayList(u8) {
    var program = std.ArrayList(u8).init(alloc);
    for (text) |c| {
        if (VirtualMachine.isOperand(c)) {
            try program.append(c);
        }
    }
    // var iter_lines = std.mem.tokenizeScalar(u8, text, '\n');
    // while (iter_lines.next()) |line| {
    //     const index_of_comment = std.mem.indexOf(u8, line, "//");
    //     if (index_of_comment) |i| {
    //         var words_it = std.mem.tokenizeAny(u8, line[0..i], " \t");
    //         while (words_it.next()) |w| {
    //             try program.appendSlice(w);
    //         }
    //     } else {
    //         var words_it = std.mem.tokenizeAny(u8, line, " \t");
    //         while (words_it.next()) |w| {
    //             try program.appendSlice(w);
    //         }
    //     }
    // }
    return program;
}

const TermCooker = struct {
    const Self = @This();
    const terminal_flags_to_remove = std.os.system.ECHO | std.os.system.ICANON;
    termios: std.os.system.termios,
    file: std.fs.File,

    fn init(file: std.fs.File) !Self {
        return .{
            .termios = try std.os.tcgetattr(file.handle),
            .file = file,
        };
    }
    fn unCookTerminal(self: *Self) !void {

        // Set to 0 echo and icanon flags
        self.termios.lflag &= ~@as(std.os.system.tcflag_t, terminal_flags_to_remove);
        try std.os.tcsetattr(self.file.handle, .FLUSH, self.termios);
    }

    fn reCookTerminal(self: *Self) void {
        self.termios.lflag |= @as(std.os.system.tcflag_t, terminal_flags_to_remove);
        std.os.tcsetattr(self.file.handle, .FLUSH, self.termios) catch {
            std.log.err("*IMPORTANT* Error while trying to reset terminal to previous state.", .{});
            std.log.err("*IMPORTANT* Fix it by blindly typing reset and enter", .{});
        };
    }
};

pub fn main() !u8 {
    var args_it = std.process.args();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const program_name = args_it.next().?;
    const filename = args_it.next() orelse {
        std.log.err("You have to provide a filename", .{});
        std.log.err("Usage: {s} <program> ", .{program_name});
        return 0xff;
    };

    var program = try loadProgram(alloc, filename);
    defer program.deinit();

    var tc = try TermCooker.init(stdin);

    // std.log.info("Executing program: \"{s}\"", .{program.items});
    try tc.unCookTerminal();
    defer tc.reCookTerminal();
    var vm = VirtualMachine.init(program.items);
    vm.execute_program() catch |err| {
        std.log.err("Error executing machine", .{});
        switch (err) {
            error.UnmatchedOpeningBracket,
            error.UnmatchedClosingBracket,
            error.OutOfBoundsPtr,
            error.InvalidInstruction,
            => {
                std.log.err("{}", .{err});
                // std.log.err("Final state = {}", .{vm});
            },
            else => return err,
        }
        return 0xff;
    };

    // std.log.info("Final state:", .{});
    // std.log.info("    ptr = {}, iptr = {}", .{ vm.ptr, vm.iptr });
    // std.log.info("    Memory: {any}", .{vm.memory});
    try stdout.writeByte('\n');
    return 0;
}
