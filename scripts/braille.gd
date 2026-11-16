extends RefCounted
## Standard 6-dot braille (Grade 1 letters + number sign).
## Dots: 1 4
##       2 5
##       3 6

const LETTERS := {
	"a": [1], "b": [1, 2], "c": [1, 4], "d": [1, 4, 5], "e": [1, 5],
	"f": [1, 2, 4], "g": [1, 2, 4, 5], "h": [1, 2, 5], "i": [2, 4], "j": [2, 4, 5],
	"k": [1, 3], "l": [1, 2, 3], "m": [1, 3, 4], "n": [1, 3, 4, 5], "o": [1, 3, 5],
	"p": [1, 2, 3, 4], "q": [1, 2, 3, 4, 5], "r": [1, 2, 3, 5], "s": [2, 3, 4],
	"t": [2, 3, 4, 5], "u": [1, 3, 6], "v": [1, 2, 3, 6], "w": [2, 4, 5, 6],
	"x": [1, 3, 4, 6], "y": [1, 3, 4, 5, 6], "z": [1, 3, 5, 6],
}
const NUMBER_SIGN := [3, 4, 5, 6]
const DIGITS := "jabcdefghi"   # 0 -> j, 1 -> a ... 9 -> i


## Returns one Array of dot numbers per braille cell.
static func cells_for(text: String) -> Array:
	var out := []
	var in_number := false
	for ch in text.to_lower():
		if ch >= "0" and ch <= "9":
			if not in_number:
				out.append(NUMBER_SIGN)
				in_number = true
			out.append(LETTERS[DIGITS[int(ch)]])
		elif LETTERS.has(ch):
			out.append(LETTERS[ch])
			in_number = false
		else:
			out.append([])
			in_number = false
	return out


## Column/row of a dot inside its 2x3 cell.
static func dot_offset(dot: int) -> Vector2i:
	return Vector2i(0 if dot <= 3 else 1, (dot - 1) % 3)
