extends RefCounted

const CANONICAL_HASH_VERSION := 1

static func is_integral_number(value: Variant) -> bool:
	match typeof(value):
		TYPE_INT:
			return true
		TYPE_FLOAT:
			var number: float = float(value)
			return is_finite(number) and number == floor(number)
		_:
			return false

static func stringify(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			var number: float = float(value)
			if not is_finite(number) or number != floor(number):
				push_error("Canonical gameplay JSON permits only finite integral numeric values")
				return ""
			return str(int(number))
		TYPE_STRING, TYPE_STRING_NAME:
			return JSON.stringify(str(value))
		TYPE_ARRAY:
			var parts: Array[String] = []
			for item in value:
				parts.append(stringify(item))
			return "[" + ",".join(parts) + "]"
		TYPE_DICTIONARY:
			return _stringify_dictionary(value)
		_:
			push_error("Unsupported canonical value type: %s" % type_string(typeof(value)))
			return ""

static func sha256(value: Variant) -> String:
	var context := HashingContext.new()
	var error := context.start(HashingContext.HASH_SHA256)
	if error != OK:
		push_error("Unable to start SHA-256 context: %s" % error_string(error))
		return ""
	context.update(stringify(value).to_utf8_buffer())
	return context.finish().hex_encode()

static func _stringify_dictionary(value: Dictionary) -> String:
	var keys: Array[String] = []
	for raw_key in value.keys():
		if not (raw_key is String) and not (raw_key is StringName):
			push_error("Canonical dictionary keys must be strings: %s" % str(raw_key))
			return ""
		keys.append(str(raw_key))
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		parts.append(JSON.stringify(key) + ":" + stringify(value[key]))
	return "{" + ",".join(parts) + "}"
