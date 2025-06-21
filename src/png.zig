const std = @import("std");

pub const Ihdr = struct {
    width: usize,
    height: usize,
    bit_depth: u8,
    color_type: u8,
    compression_method: u8,
    filter_method: u8,
    interlace_method: u8,

    pub fn toBytes(self: Ihdr, allocator: std.mem.Allocator) ![]u8 {
        var bytes = std.ArrayList(u8).init(allocator);
        defer bytes.deinit();

        try bytes.appendSlice(&.{
            @intCast(self.width >> 24 & 0xFF),
            @intCast(self.width >> 16 & 0xFF),
            @intCast(self.width >> 8 & 0xFF),
            @intCast(self.width & 0xFF),
        });
        try bytes.appendSlice(&.{
            @intCast(self.height >> 24 & 0xFF),
            @intCast(self.height >> 16 & 0xFF),
            @intCast(self.height >> 8 & 0xFF),
            @intCast(self.height & 0xFF),
        });
        try bytes.append(self.bit_depth);
        try bytes.append(self.color_type);
        try bytes.append(self.compression_method);
        try bytes.append(self.filter_method);
        try bytes.append(self.interlace_method);

        return bytes.toOwnedSlice();
    }
};

fn crc32(data: []const u8) u32 {
    const crc = std.hash.Crc32.hash(data);
    return crc;
}

pub fn createImage(allocator: std.mem.Allocator, raw_data: [][]u8) ![]u8 {
    const data = try scaleImage(allocator, raw_data, 5);
    const height: usize = data.len;
    const width: usize = data[0].len;

    var image_data = std.ArrayList(u8).init(allocator);
    defer image_data.deinit();

    // PNG header
    try image_data.appendSlice(&.{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A });

    // IHDR chunk
    var ihdr_buffer = std.ArrayList(u8).init(allocator);
    try ihdr_buffer.appendSlice(&.{ 0x00, 0x00, 0x00, 0x0D });
    try ihdr_buffer.appendSlice(&.{ 0x49, 0x48, 0x44, 0x52 });
    const ihdr = Ihdr{
        .width = width,
        .height = height,
        .bit_depth = 8,
        .color_type = 0,
        .compression_method = 0,
        .filter_method = 0,
        .interlace_method = 0,
    };
    const ihdr_bytes = try ihdr.toBytes(allocator);
    defer allocator.free(ihdr_bytes);
    try ihdr_buffer.appendSlice(ihdr_bytes);
    // Skip the first 8 bytes of the IHDR chunk for CRC calculation
    var crc_hash = crc32(ihdr_buffer.items[4..]);
    try ihdr_buffer.appendSlice(&.{
        @intCast(crc_hash >> 24 & 0xFF),
        @intCast(crc_hash >> 16 & 0xFF),
        @intCast(crc_hash >> 8 & 0xFF),
        @intCast(crc_hash & 0xFF),
    });

    try image_data.appendSlice(ihdr_buffer.items);
    ihdr_buffer.deinit();

    var pixel_data = std.ArrayList(u8).init(allocator);
    for (data) |row| {
        // No filter
        try pixel_data.append(0);
        try pixel_data.appendSlice(row);
    }

    // Compress the pixel data
    var output_buffer = std.ArrayList(u8).init(allocator);
    var compressor = try std.compress.zlib.compressor(output_buffer.writer(), .{});
    var fbs = std.io.fixedBufferStream(pixel_data.items);
    const reader = fbs.reader();
    try compressor.compress(reader);
    try compressor.finish();
    pixel_data.deinit();

    var idat_chunk = std.ArrayList(u8).init(allocator);
    const output_buffer_len = output_buffer.items.len;
    try idat_chunk.appendSlice(&.{
        @intCast((output_buffer_len >> 24) & 0xFF),
        @intCast((output_buffer_len >> 16) & 0xFF),
        @intCast((output_buffer_len >> 8) & 0xFF),
        @intCast(output_buffer_len & 0xFF),
    });
    // IDAT in hex
    try idat_chunk.appendSlice(&.{ 0x49, 0x44, 0x41, 0x54 });
    try idat_chunk.appendSlice(output_buffer.items);
    crc_hash = crc32(idat_chunk.items[4..]);
    try idat_chunk.appendSlice(&.{
        @intCast(crc_hash >> 24 & 0xFF),
        @intCast(crc_hash >> 16 & 0xFF),
        @intCast(crc_hash >> 8 & 0xFF),
        @intCast(crc_hash & 0xFF),
    });
    try image_data.appendSlice(idat_chunk.items);
    idat_chunk.deinit();

    // IEND chunk
    var iend_chunk = std.ArrayList(u8).init(allocator);
    try iend_chunk.appendSlice(&.{ 0x00, 0x00, 0x00, 0x00 });
    try iend_chunk.appendSlice(&.{ 0x49, 0x45, 0x4E, 0x44 });
    crc_hash = crc32(iend_chunk.items[4..]);
    try iend_chunk.appendSlice(&.{
        @intCast(crc_hash >> 24 & 0xFF),
        @intCast(crc_hash >> 16 & 0xFF),
        @intCast(crc_hash >> 8 & 0xFF),
        @intCast(crc_hash & 0xFF),
    });
    try image_data.appendSlice(iend_chunk.items);
    iend_chunk.deinit();

    return image_data.toOwnedSlice();
}

fn scaleImage(
    alloc: std.mem.Allocator,
    input: [][]u8,
    scale: usize,
) ![][]u8 {
    const input_height: usize = input.len;
    if (input_height == 0) return error.InvalidInput;
    const input_width: usize = input[0].len;

    const output_height: usize = input_height * scale;
    const output_width: usize = input_width * scale;

    const output = try alloc.alloc([]u8, output_height);
    for (output) |*row| {
        row.* = try alloc.alloc(u8, output_width);
    }

    var i: usize = 0;
    while (i < input_height) : (i += 1) {
        var j: usize = 0;
        while (j < input_width) : (j += 1) {
            const pixel = input[i][j];

            var di: usize = 0;
            while (di < scale) : (di += 1) {
                var dj: usize = 0;
                while (dj < scale) : (dj += 1) {
                    output[i * scale + di][j * scale + dj] = pixel;
                }
            }
        }
    }

    return output;
}
