// zig fmt: off
const std = @import("std");
const builtin = @import("builtin");
const Pkg = std.build.Pkg;
const string = []const u8;

pub const cache = ".zigmod/deps";

pub fn addAllTo(exe: *std.build.LibExeObjStep) void {
    checkMinZig(builtin.zig_version, exe);
    @setEvalBranchQuota(1_000_000);
    for (packages) |pkg| {
        exe.addPackage(pkg.pkg.?);
    }
    var llc = false;
    var vcpkg = false;
    inline for (comptime std.meta.declarations(package_data)) |decl| {
        const pkg = @as(Package, @field(package_data, decl.name));
        for (pkg.system_libs) |item| {
            exe.linkSystemLibrary(item);
            llc = true;
        }
        for (pkg.frameworks) |item| {
            if (!std.Target.current.isDarwin()) @panic(exe.builder.fmt("a dependency is attempting to link to the framework {s}, which is only possible under Darwin", .{item}));
            exe.linkFramework(item);
            llc = true;
        }
        inline for (pkg.c_include_dirs) |item| {
            exe.addIncludeDir(@field(dirs, decl.name) ++ "/" ++ item);
            llc = true;
        }
        inline for (pkg.c_source_files) |item| {
            exe.addCSourceFile(@field(dirs, decl.name) ++ "/" ++ item, pkg.c_source_flags);
            llc = true;
        }
        vcpkg = vcpkg or pkg.vcpkg;
    }
    if (llc) exe.linkLibC();
    if (builtin.os.tag == .windows and vcpkg) exe.addVcpkgPaths(.static) catch |err| @panic(@errorName(err));
}

pub const Package = struct {
    directory: string,
    pkg: ?Pkg = null,
    c_include_dirs: []const string = &.{},
    c_source_files: []const string = &.{},
    c_source_flags: []const string = &.{},
    system_libs: []const string = &.{},
    frameworks: []const string = &.{},
    vcpkg: bool = false,
};

fn checkMinZig(current: std.SemanticVersion, exe: *std.build.LibExeObjStep) void {
    const min = std.SemanticVersion.parse("0.10.0-dev.2625+d506275a0") catch return;
    if (current.order(min).compare(.lt)) @panic(exe.builder.fmt("Your Zig version v{} does not meet the minimum build requirement of v{}", .{current, min}));
}

pub const dirs = struct {
    pub const _root = "";
    pub const _eje8wf3r4lz8 = cache ++ "/../..";
    pub const _deeztnhr07fk = cache ++ "/git/github.com/zenith391/capy";
    pub const _hm449ur2xup4 = cache ++ "/git/github.com/Luukdegram/apple_pie";
};

pub const package_data = struct {
    pub const _eje8wf3r4lz8 = Package{
        .directory = dirs._eje8wf3r4lz8,
    };
    pub const _deeztnhr07fk = Package{
        .directory = dirs._deeztnhr07fk,
        .pkg = Pkg{ .name = "capy", .source = .{ .path = dirs._deeztnhr07fk ++ "/build_capy.zig" }, .dependencies = null },
    };
    pub const _hm449ur2xup4 = Package{
        .directory = dirs._hm449ur2xup4,
        .pkg = Pkg{ .name = "apple_pie", .source = .{ .path = dirs._hm449ur2xup4 ++ "/src/apple_pie.zig" }, .dependencies = null },
    };
    pub const _root = Package{
        .directory = dirs._root,
    };
};

pub const packages = &[_]Package{
};

pub const pkgs = struct {
};

pub const imports = struct {
    pub const capy = @import(".zigmod/deps/git/github.com/zenith391/capy/build_capy.zig");
    pub const apple_pie = @import(".zigmod/deps/git/github.com/Luukdegram/apple_pie/src/apple_pie.zig");
};
