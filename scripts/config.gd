extends RefCounted
## Every tunable in one place, so the game can be re-mapped onto real uDot
## hardware (different pin counts, refresh speeds, button layouts) without
## touching game logic.

# --- Logical playfield (what the child reasons about) ---------------------
const FIELD_W := 9            # cells across  (x = 1..9, single braille digit)
const FIELD_H := 9            # cells up      (y = 1..9)
const PINS_PER_CELL := 2      # each cell is a 2x2 block of pins

# --- Physical pin canvas (what the display renders) -----------------------
const CANVAS_W := 27          # pins across (fits 9 braille cells on the status line)
const CANVAS_H := 26          # pins down
const FIELD_OX := 5           # first pin column of the field (col 3 = ticks, col 4 = y-axis)
const FIELD_OY := 1           # first pin row of the field
const BRAILLE_OY := 23        # top pin row of the braille status line (3 rows tall)

# --- Device behaviour simulation ------------------------------------------
const REFRESH_INTERVAL := 0.2 # seconds between full-frame pin refreshes (slow tactile refresh)
const PIN_RISE_TIME := 0.12   # visual: how long a pin takes to rise or fall

# --- Rules ------------------------------------------------------------------
const CHAIN_AT := 3           # finding this many mines triggers a chain defuse
const MISS_PENALTY := 5.0     # seconds burned off the fuse for digging an empty spot
const TUTORIAL_MINE := Vector2i(6, 5)

# --- Levels -----------------------------------------------------------------
# Mines are every whole-number x in [x_from, x_to] where y = slope * x + offset
# lands inside the field. pings = detector charges, fuse = seconds.
const LEVELS := [
	{
		"name": "Training",
		"tutorial": true,
		"slope": 0, "offset": 3, "x_from": 1, "x_to": 9,
		"pings": 0, "fuse": 120.0,
		"rule": "Every mine was 3 up. A flat line!",
	},
	{
		"name": "Flat Row",
		"slope": 0, "offset": 6, "x_from": 1, "x_to": 9,
		"pings": 6, "fuse": 90.0,
		"rule": "Every mine was 6 up. A flat line!",
	},
	{
		"name": "Staircase",
		"slope": 1, "offset": 0, "x_from": 1, "x_to": 9,
		"pings": 5, "fuse": 80.0,
		"rule": "1 across, 1 up, every time. A staircase line!",
	},
	{
		"name": "Downhill",
		"slope": -1, "offset": 10, "x_from": 1, "x_to": 9,
		"pings": 5, "fuse": 75.0,
		"rule": "1 across, 1 down, every time. A downhill line!",
	},
	{
		"name": "Steep Stairs",
		"slope": 2, "offset": -1, "x_from": 1, "x_to": 5,
		"pings": 4, "fuse": 70.0,
		"rule": "1 across, 2 up, every time. The steepest line yet!",
	},
]
