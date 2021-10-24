const zgt = @import("zgt");
const std = @import("std");
const TextBuffer = @import("buffer.zig").TextBuffer;

const StyleComponent = struct {
    start: usize,
    end: usize,
    color: ?u24 = null,

    pub fn extractColor(rgb: u24) [3]f32 {
        return [3]f32 {
            @intToFloat(f32, (rgb >> 16) & 0xFF) / 255,
            @intToFloat(f32, (rgb >>  8) & 0xFF) / 255,
            @intToFloat(f32, (rgb      ) & 0xFF) / 255,
        };
    }
};

const Styling = struct {
    components: []const StyleComponent
};

const KeywordType = enum {
    /// Type declarations (enum, struct, fn)
    Type,
    /// Basically the rest
    ControlFlow,
    Identifier,
    Value,
    String,
    Comment,
    None,

    pub fn getColor(self: KeywordType) ?u24 {
        return switch (self) {
            .Type        => 0x0099CC,
            .ControlFlow => 0xFF0000,
            .Identifier  => null, // default color
            .String      => 0xCCAA00,
            .Comment     => 0x888888,
            .Value       => 0x0000FF,
            else         => null
        };
    }
};

const tagArray = std.enums.directEnumArrayDefault(std.zig.Token.Tag, KeywordType, .None, 0, .{
    .keyword_return = .ControlFlow,
    .keyword_try = .ControlFlow,
    .keyword_if = .ControlFlow,
    .keyword_else = .ControlFlow,
    .keyword_defer = .ControlFlow,
    .keyword_while = .ControlFlow,
    .keyword_switch = .ControlFlow,
    .keyword_catch = .ControlFlow,
    .builtin = .ControlFlow,
    .bang = .ControlFlow,

    .keyword_pub = .ControlFlow, // TODO: .Modifier ?
    .keyword_usingnamespace = .ControlFlow,

    .keyword_fn = .Type,
    .keyword_struct = .Type,
    .keyword_enum = .Type,

    .keyword_var = .ControlFlow,
    .keyword_const = .ControlFlow,

    .doc_comment = .Comment,
    .container_doc_comment = .Comment,

    .integer_literal = .Value,
    .float_literal = .Value,

    .char_literal = .String,
    .string_literal = .String,
    .multiline_string_literal_line = .String,

    .identifier = .Identifier,
});

pub const FlatText_Impl = struct {
    pub usingnamespace zgt.internal.All(FlatText_Impl);

    peer: ?zgt.backend.Canvas = null,
    handlers: FlatText_Impl.Handlers = undefined,
    dataWrappers: FlatText_Impl.DataWrappers = .{},

    buffer: *TextBuffer,
    styling: Styling,
    cursor: usize = 0,
    scrollY: u32 = 0,

    pub fn init(buffer: *TextBuffer) FlatText_Impl {
        return FlatText_Impl.init_events(FlatText_Impl {
            .buffer = buffer,
            .styling = Styling { .components = &[0]StyleComponent {} }
        });
    }

    fn keyTyped(self: *FlatText_Impl, key: []const u8) !void {
        var finalKey = key;
        if (std.mem.eql(u8, key, "\x08")) { // backspace
            if (self.cursor > 0) {
                const removed = try self.buffer.removeBackwards(self.cursor, 1);
                self.cursor -= removed;
            }
            return;
        } else if (std.mem.eql(u8, key, "\t")) {
            finalKey = "    ";
        } else if (std.mem.eql(u8, key, "\r")) {
            finalKey = "\n";
        }

        try self.buffer.append(self.cursor, finalKey);
        self.cursor += finalKey.len;
    }

    fn mouseButton(self: *FlatText_Impl, button: zgt.MouseButton, pressed: bool, x: u32, y: u32) !void {
        if (pressed) { // on press
            if (button == .Left) {
                var layout = zgt.DrawContext.TextLayout.init();
                defer layout.deinit();
                layout.setFont(.{ .face = "Fira Code", .size = 10.0 });

                const text = self.buffer.text.get();

                var buffer: [64]u8 = undefined;
                const nlines = @intCast(u32, std.mem.count(u8, text, "\n"));
                const maxLineText = try std.fmt.bufPrint(&buffer, "{d}    ", .{ nlines });
                const lineBarWidth = layout.getTextSize(maxLineText).width;

                var sx = x;
                if (sx >= lineBarWidth) {
                    sx -= lineBarWidth;
                } else {
                    sx = 0;
                }

                // TODO: use array of line starts, and divide cursor Y by 16 to get index into it
                // This would make this much faster but would only work if all lines are same size
                var lines = std.mem.split(u8, text, "\n");
                var lineY: u32 = 0;

                self.cursor = text.len - 1; // By default cursor is at the end
                while (lines.next()) |line| {
                    if (y + self.scrollY >= lineY and y + self.scrollY <= lineY + 16) {
                        const lineStart = (lines.index orelse text.len) - line.len - 1;
                        self.cursor = lineStart + line.len;

                        var size = layout.getTextSize(line);
                        while (size.width > sx and self.cursor > lineStart) {
                            self.cursor -= 1;
                            size = layout.getTextSize(line[0..self.cursor-lineStart]);
                        }
                        break;
                    }
                    lineY += 16;
                }
                self.requestDraw() catch unreachable;
            }
        }
    }

    fn mouseScroll(self: *FlatText_Impl, dx: f32, dy: f32) !void {
        const sensitivity = 48;
        _ = dx;

        if (dy > 0) {
            self.scrollY += @floatToInt(u32, @ceil(dy)) * sensitivity;
        } else {
            const inc = @floatToInt(u32, @ceil(-dy));
            if (inc < self.scrollY) {
                self.scrollY -= inc * sensitivity;
            } else {
                self.scrollY = 0;
            }
        }
        self.requestDraw() catch unreachable;
    }

    pub fn draw(self: *FlatText_Impl, ctx: zgt.DrawContext) !void {
        const width = self.getWidth();
        const height = self.getHeight();

        ctx.setColor(1, 1, 1);
        ctx.rectangle(0, 0, width, height);
        ctx.fill();

        var layout = zgt.DrawContext.TextLayout.init();
        defer layout.deinit();
        ctx.setColor(0, 0, 0);
        layout.setFont(.{ .face = "Fira Code", .size = 10.0 });

        const text = self.buffer.text.get();

        var buffer: [64]u8 = undefined;
        const nlines = @intCast(u32, std.mem.count(u8, text, "\n"));
        const maxLineText = try std.fmt.bufPrint(&buffer, "{d}    ", .{ nlines });
        const lineBarWidth = @intCast(i32, layout.getTextSize(maxLineText).width);
        var lineNum: u32 = 1;
        var lines = std.mem.split(u8, text, "\n");

        var lineY: i32 = -@intCast(i32, self.scrollY);
        var compIndex: usize = 0;
        while (lines.next()) |line| {
            if (lineY > height) {
                break;
            }

            const lineHeight = 16;
            const lineStart = (lines.index orelse text.len) - line.len - 1;
            ctx.text(0, lineY, layout, try std.fmt.bufPrint(&buffer, "{d: >4}", .{ lineNum }));

            var startIdx: usize = 0;
            var lineX: i32 = 0;
            while (compIndex < self.styling.components.len and self.styling.components[compIndex].start < lineStart + line.len) : (compIndex += 1) {
                const comp = self.styling.components[compIndex];
                const slice = text[comp.start..comp.end];
                const colors = StyleComponent.extractColor(comp.color orelse 0x000000);

                // if lineY < 0, we still need to update compIndex but not to draw text
                if (lineY > -lineHeight) {
                    ctx.setColor(0, 0, 0);
                    ctx.text(lineBarWidth + lineX, lineY, layout, line[startIdx..(comp.start-lineStart)]);
                    lineX += @intCast(i32, layout.getTextSize(line[startIdx..(comp.start-lineStart)]).width);

                    ctx.setColor(colors[0], colors[1], colors[2]);
                    ctx.text(lineBarWidth + lineX, lineY, layout, slice);
                    lineX += @intCast(i32, layout.getTextSize(slice).width);
                }
                startIdx = comp.end - lineStart;
            }
            ctx.setColor(0, 0, 0);
            ctx.text(lineBarWidth + lineX, lineY, layout, line[startIdx..]);
            if (self.cursor >= lineStart and self.cursor <= lineStart + line.len and lineY >= 0) {
                const charPos = self.cursor - lineStart;
                const x = layout.getTextSize(line[0..charPos]).width;
                ctx.line(@intCast(u32, lineBarWidth)+x, @intCast(u32, lineY), @intCast(u32, lineBarWidth)+x, @intCast(u32, lineY + 16));
            }

            lineY += lineHeight;
            lineNum += 1;
        }
    }

    pub fn updateStyle(self: *FlatText_Impl) !void {
        self.buffer.allocator.free(self.styling.components);

        // TODO: make the tokenizer asynchronous as on medium-size files it takes a lot of CPU time
        var components = std.ArrayList(StyleComponent).init(self.buffer.allocator);

        const textZ = try self.buffer.allocator.dupeZ(u8, self.buffer.text.get());
        defer self.buffer.allocator.free(textZ);

        var tokenizer = std.zig.Tokenizer.init(textZ);
        while (true) {
            const token = tokenizer.next();
            if (token.tag == .eof) break;
            //std.log.info("{s} \"{s}\"", .{@tagName(token.tag), textZ[token.loc.start..token.loc.end]});

            const keywordType = tagArray[@enumToInt(token.tag)];
            if (keywordType.getColor()) |color| {
                try components.append(.{
                    .start = token.loc.start,
                    .end = token.loc.end,
                    .color = color
                });
            }
        }
        self.styling = Styling { .components = components.toOwnedSlice() };
    }

    /// When the text is changed in the StringDataWrapper
    fn wrapperTextChanged(newValue: []const u8, userdata: usize) void {
        _ = newValue;
        const self = @intToPtr(*FlatText_Impl, userdata);
        self.updateStyle() catch unreachable;
        self.requestDraw() catch unreachable;
    }

    pub fn show(self: *FlatText_Impl) !void {
        if (self.peer == null) {
            self.peer = try zgt.backend.Canvas.create();
            try self.show_events();
            
            _ = try self.buffer.text.addChangeListener(.{
                .function = wrapperTextChanged,
                .userdata = @ptrToInt(&self.peer)
            });
            self.buffer.text.set(self.buffer.text.get());
        }
    }

    pub fn getPreferredSize(self: *FlatText_Impl, available: zgt.Size) zgt.Size {
        _ = self;
        _ = available;
        return zgt.Size { .width = 100.0, .height = 100.0 };
    }
};

pub const FlatTextConfig = struct {
    buffer: *TextBuffer
};

pub fn FlatText(config: FlatTextConfig) !FlatText_Impl {
    var textEditor = FlatText_Impl.init(config.buffer);
    _ = try textEditor.addDrawHandler(FlatText_Impl.draw);
    _ = try textEditor.addMouseButtonHandler(FlatText_Impl.mouseButton);
    _ = try textEditor.addScrollHandler(FlatText_Impl.mouseScroll);
    _ = try textEditor.addKeyTypeHandler(FlatText_Impl.keyTyped);
    return textEditor;
}
turn textEditor;
}
