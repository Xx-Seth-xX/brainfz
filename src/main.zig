const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn();

const Op = struct {
    const Kind = enum(u8) {
        inc = '+',
        dec = '-',
        incp = '>',
        decp = '<',
        out = '.',
        in = ',',
        loopb = '[',
        loope = ']',
    };
    const list = "+-><.,[]";
    fn isOp(c: u8) bool {
        return std.mem.indexOfScalar(u8, list, c) != null;
    }
    kind: Kind,
    operand: usize,
};

const VirtualMachine = struct {
    const Self = @This();
    const size: comptime_int = 1024;
    const MemType = u8;
    const debug: bool = false;
    const Error = error{RuntimeError};

    memory: [size]MemType,
    ptr: usize,
    program: []const Op,
    iptr: usize,

    // > 	Increment the data pointer by one (to point to the next cell to the right).
    // < 	Decrement the data pointer by one (to point to the next cell to the left).
    // + 	Increment the byte at the data pointer by one.
    // - 	Decrement the byte at the data pointer by one.
    // . 	Output the byte at the data pointer.
    // , 	Accept one byte of input, storing its value in the byte at the data pointer.
    // [ 	If the byte at the data pointer is zero,
    // then instead of moving the instruction pointer forward to the next command,
    // jump it forward to the command after the matching ] command.
    // ] 	If the byte at the data pointer is nonzero,
    // then instead of moving the instruction pointer forward to the next command
    // , jump it back to the command after the matching [ command.[a]
    fn execute_program(self: *Self) !void {
        while (self.iptr < self.program.len) {
            const op = self.program[self.iptr];
            switch (op.kind) {
                Op.Kind.inc => {
                    self.setAt(self.getAt() +% @as(MemType, @truncate(op.operand)));
                    self.iptr += 1;
                },
                Op.Kind.dec => {
                    self.setAt(self.getAt() -% @as(MemType, @truncate(op.operand)));
                    self.iptr += 1;
                },
                Op.Kind.incp => {
                    const res = @addWithOverflow(self.ptr, op.operand);
                    if (res[1] == 1 or res[0] >= self.memory.len) {
                        std.log.err("Overflowed memory while executing machine", .{});
                        return Error.RuntimeError;
                    }
                    self.ptr = res[0];
                    self.iptr += 1;
                },
                Op.Kind.decp => {
                    const res = @subWithOverflow(self.ptr, op.operand);
                    if (res[1] == 1) {
                        std.log.err("Underflowed memory while executing machine", .{});
                        return Error.RuntimeError;
                    }
                    self.ptr = res[0];
                    self.iptr += 1;
                },
                Op.Kind.out => {
                    const byte = self.getAt();
                    try stdout.writeByteNTimes(byte, op.operand);
                    self.iptr += 1;
                },
                Op.Kind.in => {
                    var buff: [1]u8 = undefined;
                    for (0..op.operand) |_| {
                        _ = try stdin.read(&buff);
                    }
                    self.setAt(buff[0]);
                    self.iptr += 1;
                },
                Op.Kind.loopb => {
                    if (self.getAt() == 0) {
                        self.iptr = op.operand;
                    } else {
                        self.iptr += 1;
                    }
                },
                Op.Kind.loope => {
                    if (self.getAt() != 0) {
                        self.iptr = op.operand;
                    } else {
                        self.iptr += 1;
                    }
                },
            }
        }
    }
    fn reset(self: *Self) void {
        self.iptr = 0;
        self.ptr = 0;
        self.memory = [_]MemType{0} ** size;
    }
    fn init(program: []const Op) Self {
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
};

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

const Lexer = struct {
    const Self = @This();
    buff: []const u8,
    pos: usize,

    fn next(self: *Self) ?u8 {
        while (self.pos < self.buff.len) {
            const c = self.buff[self.pos];
            self.pos += 1;
            if (Op.isOp(c)) {
                return c;
            }
        }
        return null;
    }
};

const ParseError = error{UnmatchedBracket};
fn parseProgram(alloc: std.mem.Allocator, text: []const u8) !std.ArrayList(Op) {
    var program = try std.ArrayList(Op).initCapacity(alloc, 1024);
    errdefer program.deinit();

    errdefer |err| {
        if (err == ParseError.UnmatchedBracket) {
            std.log.err("Unmatched bracket found while scanning file", .{});
            //             var l_off: usize = 0;
            //             var line_n: usize = 0;
            //             while (std.mem.indexOfScalarPos(u8, program, l_off, '\n')) |nl_off| {
            //                 line_n += 1;
            //                 if (nl_off > vm.iptr) {
            //                     std.log.err("Line number: {}", .{line_n});
            //                     const offset = vm.iptr - l_off;
            //                     var buff = [_]u8{' '} ** 160;
            //                     std.log.err("{s}", .{program[l_off..nl_off]});
            //                     if (offset < buff.len) {
            //                         buff[offset] = '^';
            //                         std.log.err("{s}", .{buff[0 .. offset + 1]});
            //                     } else {
            //                         std.log.err("By the way, write shorter lines", .{});
            //                     }
            //                     break;
            //                 } else {
            //                     l_off = nl_off + 1;
            //                 }
            //             }
        }
    }
    var loop_stack = try std.ArrayList(usize).initCapacity(alloc, 256);
    defer loop_stack.deinit();

    var lexer = Lexer{ .pos = 0, .buff = text };
    var c_ = lexer.next();
    var current_op_index: usize = 0;
    while (c_) |c| : (current_op_index += 1) {
        switch (c) {
            '>', '<', '+', '-', '.', ',' => {
                var count: usize = 1;
                const kind: Op.Kind = @enumFromInt(c);
                while (lexer.next()) |oc| {
                    if (oc == c) {
                        count += 1;
                    } else {
                        try program.append(Op{ .kind = kind, .operand = count });
                        c_ = oc;
                        break;
                    }
                } else {
                    try program.append(Op{ .kind = kind, .operand = count });
                    if (loop_stack.items.len != 0) {
                        return error.UnmatchedBracket;
                    } else {
                        return program;
                    }
                }
            },
            '[' => {
                try loop_stack.append(current_op_index);
                try program.append(Op{ .kind = Op.Kind.loopb, .operand = 0 });
                c_ = lexer.next();
            },
            ']' => {
                const matching_op_i = loop_stack.popOrNull() orelse {
                    return error.UnmatchedBracket;
                };
                program.items[matching_op_i].operand = current_op_index + 1;
                try program.append(Op{ .kind = Op.Kind.loope, .operand = matching_op_i + 1 });
                c_ = lexer.next();
            },
            else => {
                c_ = lexer.next();
            },
        }
    }
    if (loop_stack.items.len != 0) {
        return error.UnmatchedBracket;
    } else {
        return program;
    }
}

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

    var file = try std.fs.cwd().openFile(filename, .{});
    const text = try file.readToEndAlloc(alloc, 1024 * 1024); // 1MB should be more than enough
    defer alloc.free(text);
    const program = parseProgram(alloc, text) catch |err| {
        switch (err) {
            error.UnmatchedBracket => return 0xff,
            else => return err,
        }
    };
    defer program.deinit();

    // for (program.items, 0..) |op, i| {
    //     std.log.info("{}: {s} ({})", .{ i, @tagName(op.kind), op.operand });
    // }

    var tc = try TermCooker.init(stdin);

    try tc.unCookTerminal();
    defer tc.reCookTerminal();
    var vm = VirtualMachine.init(program.items);
    vm.execute_program() catch |err| {
        switch (err) {
            VirtualMachine.Error.RuntimeError => return 0xff,
            else => return err,
        }
    };

    // std.log.info("Final state:", .{});
    // std.log.info("    ptr = {}, iptr = {}", .{ vm.ptr, vm.iptr });
    // std.log.info("    Memory: {any}", .{vm.memory});
    return 0;
}
