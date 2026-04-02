class_name ProtoParser

## Encodes/decodes messages for server communication.
## Uses binary protobuf wire format.

const _Codec = preload("res://scripts/proto/protobuf_codec.gd")


## Encodes a SpinRequest into binary protobuf for sending to the server.
## Wraps: GameClientToServer { command_list: [Command { spin_request: SpinRequest }] }
static func encode_spin_request(chip_index: int, arena_code: String) -> PackedByteArray:
	# SpinRequest: field 1 = chip_index (int32), field 2 = arena_code (string)
	var spin_req := PackedByteArray()
	spin_req.append_array(_Codec.encode_int32_field(1, chip_index))
	spin_req.append_array(_Codec.encode_string_field(2, arena_code))
	# Command: oneof field 1 = spin_request (message)
	var command := _Codec.encode_bytes_field(1, spin_req)
	# GameClientToServer: field 1 = command_list (repeated message)
	return _Codec.encode_bytes_field(1, command)


## Decode raw bytes and return all updates as an Array of tagged Dictionaries.
static func decode_all_updates(data: PackedByteArray) -> Array:
	var updates := []
	var fields := _Codec.decode_message(data)
	for f in fields:
		if f[0] == 1 and f[1] == 2:  # update_list entry
			var update := _decode_update(f[2] as PackedByteArray)
			if not update.is_empty():
				updates.append(update)
	return updates


static func _decode_update(buf: PackedByteArray) -> Dictionary:
	# Update: oneof { 1=game_base_info, 2=spin_response, 3=error_response }
	var fields := _Codec.decode_message(buf)
	for f in fields:
		var fn: int = f[0]
		if fn == 1 and f[1] == 2:
			return {"_type": "game_base_info", "data": _decode_game_base_info(f[2])}
		elif fn == 2 and f[1] == 2:
			return {"_type": "spin_response", "data": _decode_spin_response(f[2])}
		elif fn == 3 and f[1] == 2:
			var err := _decode_error_response(f[2])
			return {"_type": "error", "error_code": err.get("error_code", -1)}
	return {}


## Collects a repeated int32 field (handles both packed wire type 2 and non-packed wire type 0).
static func _collect_repeated_int32(arr: Array, f: Array) -> void:
	if f[1] == 2:
		arr.append_array(_Codec.decode_packed_int32(f[2]))
	elif f[1] == 0:
		arr.append(f[2] as int)


# ── Message decoders ──────────────────────────────────────────────────────────

static func _decode_game_base_info(buf: PackedByteArray) -> Dictionary:
	var result := {"chip_setting": "", "last_screen_info": null}
	for f in _Codec.decode_message(buf):
		match f[0]:
			1: result["chip_setting"] = (f[2] as PackedByteArray).get_string_from_utf8()
			2: result["last_screen_info"] = _decode_screen_info(f[2])
	return result


static func _decode_spin_response(buf: PackedByteArray) -> Dictionary:
	var result := {
		"round_result_list": [] as Array,
		"back_to_main_game": null,
		"bet_amount": 0.0,
		"pay_amount": 0.0,
		"balance": 0.0,
	}
	for f in _Codec.decode_message(buf):
		match f[0]:
			1: result["round_result_list"].append(_decode_screen_info(f[2]))
			2: result["back_to_main_game"] = _decode_screen_info(f[2])
			3: result["bet_amount"] = f[2] as float
			4: result["pay_amount"] = f[2] as float
			5: result["balance"] = f[2] as float
	return result


static func _decode_error_response(buf: PackedByteArray) -> Dictionary:
	var result := {"error_code": 0}
	for f in _Codec.decode_message(buf):
		if f[0] == 1:
			result["error_code"] = f[2] as int
	return result


static func _decode_screen_info(buf: PackedByteArray) -> Dictionary:
	var result := {
		"screen": [] as Array,
		"scnb": [] as Array,
		"elims": [] as Array,
		"scatter": null,
		"ws": 0.0,
		"stws": 0.0,
		"stg": 0,
		"eostg": false,
		"dsp": [] as Array,
		"we": [] as Array,
		"fg": null,
		"fgis": null,
		"bala": 0.0,
		"rsct": [] as Array,
	}
	for f in _Codec.decode_message(buf):
		match f[0]:
			1:  # screen - repeated SymbolDescription
				result["screen"].append(_decode_symbol_description(f[2]))
			2:  # elims - repeated EliminateInfo
				result["elims"].append(_decode_eliminate_info(f[2]))
			5:  # scnb - repeated SymbolDescription (screen before wild effects)
				if f[1] == 2:
					result["scnb"].append(_decode_symbol_description(f[2]))
			4:  # scatter
				if f[1] == 2:
					result["scatter"] = _decode_scatter_info(f[2])
			6:  # fgsp - repeated int32
				_collect_repeated_int32(result.get_or_add("fgsp", []), f)
			8:  # fg - FreeGameInfo
				if f[1] == 2:
					result["fg"] = _decode_free_game_info(f[2])
			9:  # fgis - FreeGameInitialState
				if f[1] == 2:
					result["fgis"] = _decode_free_game_initial_state(f[2])
			16: result["ws"] = f[2] as float
			17: result["stws"] = f[2] as float
			26:  # rsct - repeated int32
				_collect_repeated_int32(result["rsct"], f)
			27:  # rsctb - repeated int32 (before wild effects, matches scnb)
				_collect_repeated_int32(result.get_or_add("rsctb", []), f)
			28:  # dsp - repeated int32
				_collect_repeated_int32(result["dsp"], f)
			31: result["stg"] = f[2] as int
			32: result["eostg"] = (f[2] as int) != 0
			53: result["bala"] = f[2] as float
			101:  # we - repeated WildEffect
				if f[1] == 2:
					result["we"].append(_decode_wild_effect(f[2]))
			102:  # oelims - repeated EliminateInfo (original cluster before wild effects)
				if f[1] == 2:
					result.get_or_add("oelims", []).append(_decode_eliminate_info(f[2]))
	return result


static func _decode_symbol_description(buf: PackedByteArray) -> Dictionary:
	var result := {"sid": 0, "pos": 0, "l": 0, "w": 0, "bt": 0, "ss": 0, "mtp": 0, "ih": 0}
	for f in _Codec.decode_message(buf):
		match f[0]:
			1: result["sid"] = f[2] as int
			2: result["pos"] = f[2] as int
			3: result["l"] = f[2] as int
			4: result["w"] = f[2] as int
			5: result["bt"] = f[2] as int
			6: result["ss"] = f[2] as int
			7: result["mtp"] = f[2] as int
			9: result["ih"] = f[2] as int
	return result


static func _decode_eliminate_info(buf: PackedByteArray) -> Dictionary:
	var result := {"sid": 0, "wp": [] as Array, "ws": 0.0, "bs": 0.0, "spo": 0.0, "awmtp": 0.0, "wsbd1": 0.0, "wsbd2": 0.0}
	for f in _Codec.decode_message(buf):
		match f[0]:
			1: result["sid"] = f[2] as int
			2:  # wp - repeated int32
				_collect_repeated_int32(result["wp"], f)
			3: result["ws"] = f[2] as float
			6: result["bs"] = f[2] as float
			8: result["spo"] = f[2] as float
			10: result["awmtp"] = f[2] as float
			16: result["wsbd1"] = f[2] as float
			17: result["wsbd2"] = f[2] as float
	return result


static func _decode_scatter_info(buf: PackedByteArray) -> Dictionary:
	var result := {"sid": 0, "wp": [] as Array, "ws": 0.0, "bs": 0.0, "bl": 0.0, "spo": 0.0}
	for f in _Codec.decode_message(buf):
		match f[0]:
			1: result["sid"] = f[2] as int
			2:  # wp - repeated int32
				_collect_repeated_int32(result["wp"], f)
			3: result["ws"] = f[2] as float
			6: result["bs"] = f[2] as float
			7: result["bl"] = f[2] as float
			8: result["spo"] = f[2] as float
	return result


static func _decode_wild_effect(buf: PackedByteArray) -> Dictionary:
	var result := {"pos": 0, "effect_type": "", "affected": [] as Array, "value": 0, "wild_sub_type": 0, "changes": [] as Array}
	for f in _Codec.decode_message(buf):
		match f[0]:
			1: result["pos"] = f[2] as int
			2: result["effect_type"] = (f[2] as PackedByteArray).get_string_from_utf8()
			3:  # affected - repeated int32
				_collect_repeated_int32(result["affected"], f)
			4: result["value"] = f[2] as int
			5: result["wild_sub_type"] = f[2] as int
			6:  # changes - repeated ScreenChange
				if f[1] == 2:
					result["changes"].append(_decode_screen_change(f[2]))
	return result


static func _decode_screen_change(buf: PackedByteArray) -> Dictionary:
	var result := {"pos": 0, "to_sid": 0}
	for f in _Codec.decode_message(buf):
		match f[0]:
			1: result["pos"] = f[2] as int
			2: result["to_sid"] = f[2] as int
	return result


static func _decode_multiplier_info(buf: PackedByteArray) -> Dictionary:
	var result := {"pos": 0, "value": 0}
	for f in _Codec.decode_message(buf):
		match f[0]:
			1: result["pos"] = f[2] as int
			2: result["value"] = f[2] as int
	return result


static func _decode_free_game_info(buf: PackedByteArray) -> Dictionary:
	var result := {"tws": 0.0, "ar": 0, "lr": 0, "tr": 0, "rtssid": 0, "lrb": 0, "trb": 0, "corner_features": [] as Array}
	for f in _Codec.decode_message(buf):
		match f[0]:
			1: result["tws"] = f[2] as float
			2: result["ar"] = f[2] as int
			3: result["lr"] = f[2] as int
			4: result["tr"] = f[2] as int
			6: result["rtssid"] = f[2] as int
			7: result["lrb"] = f[2] as int
			8: result["trb"] = f[2] as int
			11:  # cf - repeated CornerFeature
				if f[1] == 2:
					result["corner_features"].append(_decode_corner_feature(f[2]))
	return result


static func _decode_free_game_initial_state(buf: PackedByteArray) -> Dictionary:
	var result := {"ac": "", "fgsct": 0, "fgct": 0, "multipliers": [] as Array}
	for f in _Codec.decode_message(buf):
		match f[0]:
			3: result["ac"] = (f[2] as PackedByteArray).get_string_from_utf8()
			6: result["fgsct"] = f[2] as int
			11: result["fgct"] = f[2] as int
			51:  # multipliers - repeated MultiplierInfo
				if f[1] == 2:
					result["multipliers"].append(_decode_multiplier_info(f[2]))
			# field 52 (initial_rows) removed — always 6
			# field 53 (corner_assignments) removed — read from screen Wild bt
	return result


static func _decode_corner_feature(buf: PackedByteArray) -> Dictionary:
	var result := {"pos": 0, "feature_type": 0, "value": 0, "generated_mpi": [], "rows": 0, "affected_mpi": []}
	for f in _Codec.decode_message(buf):
		match f[0]:
			1: result["pos"] = f[2] as int
			2: result["feature_type"] = f[2] as int
			3: result["value"] = f[2] as int
			4:  # generated_mpi - repeated MultiplierInfo (Generate only)
				if f[1] == 2:
					result["generated_mpi"].append(_decode_multiplier_info(f[2]))
			5: result["rows"] = f[2] as int
			6:  # affected_mpi - repeated MultiplierInfo (Double only)
				if f[1] == 2:
					result["affected_mpi"].append(_decode_multiplier_info(f[2]))
	return result



