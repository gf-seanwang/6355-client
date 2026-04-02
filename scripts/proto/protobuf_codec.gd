class_name ProtobufCodec

## Low-level protobuf binary wire format encoder/decoder.
## Wire types: 0=varint, 1=64-bit fixed, 2=length-delimited

# ── Encoding ──────────────────────────────────────────────────────────────────

static func encode_varint(value: int) -> PackedByteArray:
	var buf := PackedByteArray()
	# Handle negative values: use two's complement (10 bytes for 64-bit)
	if value < 0:
		value = value + (1 << 64)
	while value > 0x7F:
		buf.append((value & 0x7F) | 0x80)
		value >>= 7
	buf.append(value & 0x7F)
	return buf


static func encode_tag(field_num: int, wire_type: int) -> PackedByteArray:
	return encode_varint((field_num << 3) | wire_type)


static func encode_int32_field(field_num: int, value: int) -> PackedByteArray:
	if value == 0:
		return PackedByteArray()
	var buf := encode_tag(field_num, 0)
	buf.append_array(encode_varint(value))
	return buf


static func encode_bool_field(field_num: int, value: bool) -> PackedByteArray:
	if not value:
		return PackedByteArray()
	var buf := encode_tag(field_num, 0)
	buf.append(1)
	return buf


static func encode_string_field(field_num: int, value: String) -> PackedByteArray:
	if value.is_empty():
		return PackedByteArray()
	var str_bytes := value.to_utf8_buffer()
	var buf := encode_tag(field_num, 2)
	buf.append_array(encode_varint(str_bytes.size()))
	buf.append_array(str_bytes)
	return buf


static func encode_double_field(field_num: int, value: float) -> PackedByteArray:
	if value == 0.0:
		return PackedByteArray()
	var buf := encode_tag(field_num, 1)
	var tmp := PackedByteArray()
	tmp.resize(8)
	tmp.encode_double(0, value)
	buf.append_array(tmp)
	return buf


static func encode_bytes_field(field_num: int, data: PackedByteArray) -> PackedByteArray:
	if data.is_empty():
		return PackedByteArray()
	var buf := encode_tag(field_num, 2)
	buf.append_array(encode_varint(data.size()))
	buf.append_array(data)
	return buf


# ── Decoding ──────────────────────────────────────────────────────────────────

## Returns [value, new_pos]. Returns [-1, -1] on error.
static func decode_varint(buf: PackedByteArray, pos: int) -> Array:
	var result: int = 0
	var shift: int = 0
	while pos < buf.size():
		var b: int = buf[pos]
		pos += 1
		result |= (b & 0x7F) << shift
		if (b & 0x80) == 0:
			return [result, pos]
		shift += 7
		if shift >= 64:
			return [-1, -1]
	return [-1, -1]


## Returns [double_value, new_pos]
static func decode_fixed64(buf: PackedByteArray, pos: int) -> Array:
	if pos + 8 > buf.size():
		return [0.0, -1]
	var value: float = buf.decode_double(pos)
	return [value, pos + 8]


## Decode a single field from buf at pos.
## Returns [field_num, wire_type, value, new_pos]
## For wire_type 0: value is int
## For wire_type 1: value is float (double)
## For wire_type 2: value is PackedByteArray (sub-slice)
static func decode_field(buf: PackedByteArray, pos: int) -> Array:
	if pos >= buf.size():
		return [0, 0, null, -1]
	var tag_result := decode_varint(buf, pos)
	if tag_result[1] < 0:
		return [0, 0, null, -1]
	var tag: int = tag_result[0]
	pos = tag_result[1]
	var field_num: int = tag >> 3
	var wire_type: int = tag & 0x07

	match wire_type:
		0:  # varint
			var vr := decode_varint(buf, pos)
			if vr[1] < 0:
				return [0, 0, null, -1]
			return [field_num, wire_type, vr[0], vr[1]]
		1:  # 64-bit fixed
			var dr := decode_fixed64(buf, pos)
			if dr[1] < 0:
				return [0, 0, null, -1]
			return [field_num, wire_type, dr[0], dr[1]]
		2:  # length-delimited
			var lr := decode_varint(buf, pos)
			if lr[1] < 0:
				return [0, 0, null, -1]
			var length: int = lr[0]
			var start: int = lr[1]
			if start + length > buf.size():
				return [0, 0, null, -1]
			return [field_num, wire_type, buf.slice(start, start + length), start + length]
		5:  # 32-bit fixed
			if pos + 4 > buf.size():
				return [0, 0, null, -1]
			var val: float = buf.decode_float(pos)
			return [field_num, wire_type, val, pos + 4]
		_:
			push_error("ProtobufCodec: unsupported wire type %d" % wire_type)
			return [0, 0, null, -1]


## Decode all fields in a message buffer.
## Returns Array of [field_num, wire_type, value]
static func decode_message(buf: PackedByteArray) -> Array:
	var fields := []
	var pos := 0
	while pos < buf.size():
		var result := decode_field(buf, pos)
		if result[3] < 0:
			break
		fields.append([result[0], result[1], result[2]])
		pos = result[3]
	return fields


## Decode packed repeated int32 (wire type 2 containing varints)
static func decode_packed_int32(buf: PackedByteArray) -> Array:
	var values := []
	var pos := 0
	while pos < buf.size():
		var vr := decode_varint(buf, pos)
		if vr[1] < 0:
			break
		values.append(vr[0])
		pos = vr[1]
	return values
