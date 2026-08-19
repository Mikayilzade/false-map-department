extends RefCounted

const MAX_LENGTH := 64

static func is_valid(value: Variant) -> bool:
	if not (value is String):
		return false
	var text := value as String
	if text.length() < 2 or text.length() > MAX_LENGTH:
		return false
	var first := text.unicode_at(0)
	if not _is_ascii_letter(first):
		return false
	for index in range(text.length()):
		var code := text.unicode_at(index)
		if not (_is_ascii_letter(code) or _is_ascii_digit(code) or code == 95 or code == 45 or code == 58):
			return false
	return true

static func require(value: Variant, field_name: String) -> String:
	if not is_valid(value):
		push_error("Malformed stable ID for %s: %s" % [field_name, str(value)])
		return ""
	return value as String

static func _is_ascii_letter(code: int) -> bool:
	return (code >= 65 and code <= 90) or (code >= 97 and code <= 122)

static func _is_ascii_digit(code: int) -> bool:
	return code >= 48 and code <= 57
