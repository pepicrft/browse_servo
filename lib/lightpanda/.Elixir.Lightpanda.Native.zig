const builtin = @import("builtin");

pub fn target() []const u8 {
    return switch (builtin.target.cpu.arch) {
        .aarch64 => switch (builtin.target.os.tag) {
            .linux => "aarch64-linux-gnu",
            .macos => "aarch64-macos-none",
            else => "unsupported",
        },
        .x86_64 => switch (builtin.target.os.tag) {
            .linux => "x86_64-linux-gnu",
            .macos => "x86_64-macos-none",
            else => "unsupported",
        },
        else => "unsupported",
    };
}

pub fn executable_mode() u32 {
    return switch (builtin.target.os.tag) {
        .windows => 0,
        else => 493,
    };
}
