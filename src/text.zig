const std = @import("std");
const zgt = @import("zgt");
const TextBuffer = @import("buffer.zig").TextBuffer;

const KeywordType = enum {
    /// Type declarations (enum, struct, fn)
    Type,
    /// Built-in types (i42, f32)
    BuiltinType,
    /// Basically the rest
    ControlFlow,
    Identifier,
    Value,
    String,
    Comment,
    Operator,
    None,

    pub fn getColor(self: KeywordType) ?u24 {
        return switch (self) {
            .Type => 0x0099CC,
            .BuiltinType => 0x6699FF,
            .ControlFlow => 0xFF0000,
            .Identifier => null, // default color
            .String => 0xF0B800,
            .Comment => 0x888888,
            .Operator => 0xFF0000,
            .Value => 0xCC33FF,
            else => null,
        };
    }
};

const tagArray = std.enums.directEnumArrayDefault(std.zig.Token.Tag, KeywordType, .None, 0, .{
    .keyword_return = .ControlFlow,
    .keyword_try = .ControlFlow,
    .keyword_if = .ControlFlow,
    .keyword_else = .ControlFlow,
    .keyword_for = .ControlFlow,
    .keyword_defer = .ControlFlow,
    .keyword_while = .ControlFlow,
    .keyword_switch = .ControlFlow,
    .keyword_catch = .ControlFlow,
    .keyword_asm = .ControlFlow,
    .keyword_async = .ControlFlow,
    .keyword_await = .ControlFlow,
    .keyword_break = .ControlFlow,
    .builtin = .ControlFlow,
    .bang = .ControlFlow,

    .keyword_pub = .ControlFlow, // TODO: .Modifier ?
    .keyword_usingnamespace = .ControlFlow,

    .keyword_fn = .Type,
    .keyword_struct = .Type,
    .keyword_enum = .Type,
    .keyword_error = .Type,

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

    .plus = .Operator,
    .plus_equal = .Operator,
    .plus_percent = .Operator,
    .plus_percent_equal = .Operator,
    .minus = .Operator,
    .minus_equal = .Operator,
    .minus_percent = .Operator,
    .minus_percent_equal = .Operator,
    .asterisk = .Operator,
    .asterisk_equal = .Operator,
    .asterisk_percent = .Operator,
    .asterisk_percent_equal = .Operator,
    .slash = .Operator,
    .slash_equal = .Operator,
    .percent = .Operator,
    .percent_equal = .Operator,
    .keyword_and = .Operator,
    .keyword_or = .Operator,

    .equal = .Operator,
    .question_mark = .Operator,
});

const StyleComponent = struct {
    start: usize,
    end: usize,
    color: ?u24 = null,

    pub fn extractColor(rgb: u24) [3]f32 {
        return [3]f32{
            @intToFloat(f32, (rgb >> 16) & 0xFF) / 255,
            @intToFloat(f32, (rgb >> 8) & 0xFF) / 255,
            @intToFloat(f32, (rgb) & 0xFF) / 255,
        };
    }
};

const Styling = struct {
    components: []const StyleComponent,
    tabWidth: union(enum) {
        /// Tabs width is declared directly in pixels (not recommended as it breaks font sizes)
        Pixels: u32,
        /// Tabs width is declared in number of spaces (recommended)
        Spaces: u32,
    } = .{ .Spaces = 4 },
};

const Selection = struct {
    /// The end of the selection is the current cursor position
    start: usize,
};

pub const FlatText_Impl = struct {
    pub usingnamespace zgt.internal.All(FlatText_Impl);

    peer: ?zgt.backend.Canvas = null,
    handlers: FlatText_Impl.Handlers = undefined,
    dataWrappers: FlatText_Impl.DataWrappers = .{},

    buffer: *TextBuffer,
    styling: Styling,
    cursor: usize = 0,
    selection: ?Selection = undefined,

    /// Current scroll value (differs from target when animating)
    scrollY: u32 = 0,

    isDragging: bool = false,

    /// Target scroll value
    targetScrollY: u32 = 0,
    fontFace: [:0]const u8 = "Fira Code",

    /// The draw timer is used to count the time between draw calls
    /// This allows for constant speed regardless of any potential lag
    drawTimer: std.time.Timer = undefined,

    pub fn init(buffer: *TextBuffer) FlatText_Impl {
        return FlatText_Impl.init_events(FlatText_Impl{ .buffer = buffer, .styling = Styling{
            .components = &[0]StyleComponent{},
        }, .drawTimer = std.time.Timer.start() catch unreachable, });
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
            //finalKey = "    ";
        } else if (std.mem.eql(u8, key, "\r")) {
            finalKey = "\n";
        }

        try self.buffer.append(self.cursor, finalKey);
        self.cursor += finalKey.len;
    }

    fn getLineStart(text: []const u8, cursor: usize) usize {
        var pos: usize = cursor;
        while (pos > 0) : (pos -|= 1) {
            if (text[pos] == '\n') {
                return pos + 1;
            }
        }
        return pos;
    }

    fn getLineEnd(text: []const u8, cursor: usize) usize {
        var pos: usize = cursor;
        while (pos < text.len) : (pos += 1) {
            if (text[pos] == '\n') {
                return pos;
            }
        }
        return pos;
    }

    fn keyPressed(self: *FlatText_Impl, keycode: u16) !void {
        switch (keycode) {
            // Up cursor
            111 => {
                if (self.cursor > 0) {
                    const lineStart = getLineStart(self.buffer.text.get(), self.cursor - 1);
                    const previousLineStart = getLineStart(self.buffer.text.get(), lineStart - 2); // skip first letter and \n
                    const previousLineLength = getLineEnd(self.buffer.text.get(), previousLineStart) - previousLineStart;

                    // The position of the cursor relative to the line
                    var relCursor = self.cursor - lineStart;
                    if (relCursor > previousLineLength) {
                        relCursor = previousLineLength;
                    }
                    self.cursor = previousLineStart + relCursor;
                    self.selection = null;
                    self.requestDraw() catch unreachable;
                }
            },
            // Left cursor
            113 => {
                if (self.cursor > 0) {
                    self.cursor -= 1;
                    self.selection = null;
                    self.requestDraw() catch unreachable;
                }
            },
            // Right cursor
            114 => {
                if (self.cursor < self.buffer.length()) {
                    self.cursor += 1;
                    self.selection = null;
                    self.requestDraw() catch unreachable;
                }
            },
            // Down cursor
            116 => {
                if (self.cursor < self.buffer.length()) {
                    const lineStart = getLineStart(self.buffer.text.get(), self.cursor - 1);
                    const nextLineStart = getLineEnd(self.buffer.text.get(), self.cursor) + 1;
                    const nextLineLength = getLineEnd(self.buffer.text.get(), nextLineStart) - nextLineStart;

                    // The position of the cursor relative to the line
                    var relCursor = self.cursor - lineStart;
                    if (relCursor > nextLineLength) {
                        relCursor = nextLineLength;
                    }
                    self.cursor = nextLineStart + relCursor;
                    self.selection = null;
                    self.requestDraw() catch unreachable;
                }
            },
            else => {},
        }
    }

    fn findCursorPositionAt(self: FlatText_Impl, x: u32, y: u32) !usize {
        var cursor: usize = 0;

        var layout = zgt.DrawContext.TextLayout.init();
        defer layout.deinit();
        layout.setFont(.{ .face = self.fontFace, .size = 10.0 });

        const text = self.buffer.text.get();

        // Get the maximum width of all line numbers, by using the largest line number.
        var buffer: [64]u8 = undefined;
        const nlines = @intCast(u32, std.mem.count(u8, text, "\n"));
        // 'catch unreachable' because nlines, being a 32-bit int, won't ever be able to have 60 digits
        const maxLineText = std.fmt.bufPrint(&buffer, "{d}    ", .{nlines}) catch unreachable;
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

        cursor = text.len - 1; // By default cursor is at the end
        while (lines.next()) |line| {
            if (y + self.scrollY >= lineY and y + self.scrollY <= lineY + 16) {
                const lineStart = (lines.index orelse text.len) - line.len - 1;
                cursor = lineStart + line.len;

                var size = layout.getTextSize(line);
                while (size.width > sx and cursor > lineStart) {
                    cursor -= 1;
                    size = layout.getTextSize(line[0 .. cursor - lineStart]);
                }
                break;
            }
            lineY += 16;
        }

        return cursor;
    }

    fn mouseButton(self: *FlatText_Impl, button: zgt.MouseButton, pressed: bool, x: u32, y: u32) !void {
        if (button == .Left) {
            self.isDragging = pressed;
        }

        if (pressed) { // on press
            if (button == .Left) {
                self.selection = null;
                self.cursor = try self.findCursorPositionAt(x, y);
                self.requestDraw() catch unreachable;
            }
        }
    }

    fn mouseMoved(self: *FlatText_Impl, x: u32, y: u32) !void {
        if (self.isDragging) {
            if (self.selection == null) {
                self.selection = Selection{ .start = self.cursor };
            }
            self.cursor = try self.findCursorPositionAt(x, y);
            self.requestDraw() catch unreachable;
        }
    }

    fn mouseScroll(self: *FlatText_Impl, dx: f32, dy: f32) !void {
        const sensitivity = 48;
        _ = dx;

        if (dy > 0) {
            self.targetScrollY += @floatToInt(u32, @ceil(dy)) * sensitivity;
        } else {
            const inc = @floatToInt(u32, @ceil(-dy));
            if (inc < self.targetScrollY) {
                self.targetScrollY -= inc * sensitivity;
            } else {
                self.targetScrollY = 0;
            }
        }
        if (self.scrollY == self.targetScrollY) {
            self.drawTimer.reset();
        }
        self.requestDraw() catch unreachable;
    }

    pub fn draw(self: *FlatText_Impl, ctx: *zgt.DrawContext) !void {
        const width = self.getWidth();
        const height = self.getHeight();

        ctx.setColor(0, 0, 0);
        ctx.rectangle(0, 0, width, height);
        ctx.fill();
        //ctx.clear(0, 0, width, height);

        var layout = zgt.DrawContext.TextLayout.init();
        defer layout.deinit();
        ctx.setColor(1, 1, 1);
        layout.setFont(.{ .face = self.fontFace, .size = 10.0 });

        const text = self.buffer.text.get();

        var buffer: [64]u8 = undefined;
        const nlines = @intCast(u32, std.mem.count(u8, text, "\n"));
        const maxLineText = try std.fmt.bufPrint(&buffer, "{d}    ", .{nlines});
        const lineBarWidth = @intCast(i32, layout.getTextSize(maxLineText).width);
        var lineNum: u32 = 1;
        var lines = std.mem.split(u8, text, "\n");

        var lineY: i32 = -@intCast(i32, self.scrollY);
        var compIndex: usize = 0;
        // Iterate through every line
        while (lines.next()) |line| {
            // If we're below the component's height (that is, not visible) just
            // break out of the loop
            if (lineY > height) {
                break;
            }

            const lineHeight = 16;
            const lineStart = (lines.index orelse text.len) - line.len - 1;
            defer {
                lineY += lineHeight;
                lineNum += 1;
            }

            var startIdx: usize = 0;
            var lineX: i32 = 0;
            while (compIndex < self.styling.components.len and self.styling.components[compIndex].start < lineStart + line.len) : (compIndex += 1) {
                const comp = self.styling.components[compIndex];
                const slice = text[comp.start..comp.end];
                const colors = StyleComponent.extractColor(comp.color orelse 0xFFFFFF);

                // if lineY < 0, we still need to update compIndex but not to draw text
                if (lineY > -lineHeight) {
                    ctx.setColor(1, 1, 1);
                    ctx.text(lineBarWidth + lineX, lineY, layout, line[startIdx..(comp.start - lineStart)]);
                    lineX += @intCast(i32, layout.getTextSize(line[startIdx..(comp.start - lineStart)]).width);

                    ctx.setColor(colors[0], colors[1], colors[2]);
                    ctx.text(lineBarWidth + lineX, lineY, layout, slice);
                    lineX += @intCast(i32, layout.getTextSize(slice).width);
                }
                startIdx = comp.end - lineStart;
            }

            ctx.setColor(0.5, 0.5, 0.5); // if not detected, it's a comment
            ctx.text(lineBarWidth + lineX, lineY, layout, line[startIdx..]);
            if (self.cursor >= lineStart and self.cursor <= lineStart + line.len and lineY >= 0) {
                const charPos = self.cursor - lineStart;
                const x = layout.getTextSize(line[0..charPos]).width;
                ctx.setColor(1, 1, 1);
                ctx.line(@intCast(u32, lineBarWidth) + x, @intCast(u32, lineY), @intCast(u32, lineBarWidth) + x, @intCast(u32, lineY + 16));
            }
            ctx.text(0, lineY, layout, try std.fmt.bufPrint(&buffer, "{d: >4}", .{lineNum}));

            if (self.selection) |selection| {
                if (selection.start <= lineStart + line.len and self.cursor >= lineStart and lineY >= 0) {
                    // The position in the current line where the cursor is at
                    const lineCursorEnd = if (self.cursor >= lineStart + line.len)
                        line.len
                    else
                        self.cursor - lineStart;
                    const lineWidth = layout.getTextSize(line[0..lineCursorEnd]).width;

                    ctx.setColorRGBA(0.5, 0.5, 1.0, 0.5);
                    ctx.rectangle(@intCast(u32, lineBarWidth), @intCast(u32, lineY), lineWidth, 16);
                    ctx.fill();
                }
            }
        }

        const timeSinceLastCall = @intToFloat(f32, self.drawTimer.lap()) / @intToFloat(f32, std.time.ns_per_ms);
        const t = std.math.min(1, 0.012 * timeSinceLastCall); // clamp to 1 maximum
        const oldY = self.scrollY;
        self.scrollY = @floatToInt(u32, @intToFloat(f32, self.scrollY) * (1 - t) + @intToFloat(f32, self.targetScrollY) * t);
        if (self.scrollY != oldY) {
            self.requestDraw() catch unreachable;
        }
    }

    pub fn _deinit(self: *FlatText_Impl, widget: *zgt.Widget) void {
        _ = widget;
        self.buffer.allocator.free(self.styling.components);
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

            var keywordType = tagArray[@enumToInt(token.tag)];
            if (keywordType == .Identifier and (textZ[token.loc.start] == 'u' or textZ[token.loc.start] == 'f')) {
                const length = token.loc.end - token.loc.start;
                var isNumeralType = true;
                var i: usize = token.loc.start + 1;
                while (i < token.loc.end) : (i += 1) {
                    if (!std.ascii.isDigit(textZ[i])) {
                        isNumeralType = false;
                        break;
                    }
                }
                if (length > 1 and isNumeralType) keywordType = .BuiltinType;
            } else if (keywordType == .Identifier) {
                const tokenText = textZ[token.loc.start..token.loc.end];
                if (std.mem.eql(u8, tokenText, "true") or std.mem.eql(u8, tokenText, "false")) {
                    keywordType = .Value;
                } else if (std.mem.eql(u8, tokenText, "null")) {
                    keywordType = .Value;
                }
            }
            //if (keywordType.getColor()) |color| {
            try components.append(.{ .start = token.loc.start, .end = token.loc.end, .color = keywordType.getColor() });
            //} else {
            //    std.log.warn("No style: {}", .{ token.tag });
            //}
        }
        self.styling = Styling{ .components = components.toOwnedSlice() };
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

            _ = try self.buffer.text.addChangeListener(.{ .function = wrapperTextChanged, .userdata = @ptrToInt(&self.peer) });
            self.buffer.text.set(self.buffer.text.get());
        }
    }

    pub fn getPreferredSize(self: *FlatText_Impl, available: zgt.Size) zgt.Size {
        _ = self;
        _ = available;
        return zgt.Size{ .width = 100.0, .height = 100.0 };
    }
};

pub const FlatTextConfig = struct { buffer: *TextBuffer };

pub fn FlatText(config: FlatTextConfig) !FlatText_Impl {
    var textEditor = FlatText_Impl.init(config.buffer);
    _ = try textEditor.addDrawHandler(FlatText_Impl.draw);
    _ = try textEditor.addMouseButtonHandler(FlatText_Impl.mouseButton);
    _ = try textEditor.addMouseMotionHandler(FlatText_Impl.mouseMoved);
    _ = try textEditor.addScrollHandler(FlatText_Impl.mouseScroll);
    _ = try textEditor.addKeyTypeHandler(FlatText_Impl.keyTyped);
    _ = try textEditor.addKeyPressHandler(FlatText_Impl.keyPressed);
    return textEditor;
}
