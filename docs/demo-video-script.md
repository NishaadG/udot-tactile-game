# Mine Line: 3-minute demo video script

**Setup:** record the browser game full-screen with system audio on (OBS: Display Capture + Desktop Audio). Clear progress first so Training is the only unlocked mission: in a private/incognito window, or by clearing site data. Use **Shift+U** on the menu to unlock missions when you reach that part. Talk over the gameplay. The *italic lines* are the game's own voice, so pause and let them play.

---

### 0:00–0:20 · Hook (title screen)
**Show:** the title screen, then press a key. The game says *"Welcome to Mine Line!"*
**Say:**
> "This is Mine Line, a game for a blind 10-year-old on uDot's tactile display. A saboteur buries mines in a field, but always in a pattern. Spot the pattern and you win. The pattern is a line on a graph, so the kid is learning graphs without anyone saying the word."

### 0:20–0:45 · The display
**Show:** start Training. Press **H** to turn helper view off and on again.
**Say:**
> "On the left is a simulation of the pin display. With helper view off, this is everything the child gets: raised pins. The axes have a tick mark every step so they can count where they are. Along the bottom, the status line is real 6-dot braille: x, y, and pings left. The screen only refreshes every fifth of a second, like a real pin display."

### 0:45–1:25 · It teaches itself
**Show:** follow the tutorial. Move left into the wall (bump), press **C**, press **Space**, follow the ticks, and dig on the long tone.
**Say (in the gaps):**
> "Nobody explains the controls up front. The game asks for one action at a time and waits until the child has done it. A bump teaches the edge. C teaches coordinates as '1 across, 4 up'."
> "This is the detector. Tick speed is distance, left or right ear is direction, and pitch is up or down. And when I move up, my footsteps go up in pitch too. It's one rule everywhere: left/right is stereo, up/down is pitch."

### 1:25–2:00 · The core moment: chain defuse
**Show:** the row lesson. Dig two mines, let the robot hint play, then dig the third *without pinging*.
**Say:**
> "After two mines, the robot sidekick says they make a pattern. If I predict the third one instead of searching for it…"
> *(let the chain play)*
> "…the whole line defuses at once, and you hear the line as a melody. This is the payoff, and it only happens when you understand the pattern. The slow refresh helps here: the pins rise one by one, like dominoes."

### 2:00–2:30 · Stakes: the boom
**Show:** Shift+U on the menu, then start Mission 3 (Downhill). Dig a few wrong spots ("the fuse jumps ahead"), then let it run out. *(Tip: open the URL with `?debug` and press F2 to cut the fuse to 3 seconds.)*
**Say:**
> "Missions have a fuse and only a few pings, so guessing blindly costs you. When it runs out… *(BOOM)* …and then every mine rises so the child can feel the line they missed. Losing teaches the answer, and kids immediately want to try again."

### 2:30–2:50 · Why they come back
**Show:** win a mission: fanfare, line melody, stars. Then the menu with stars.
**Say:**
> "Stars come from pings left and no wasted digs, so the kid who understands the graph scores best. Four saboteur patterns, flat, staircase, downhill and steep, each with its own sound, and a rank from Recruit to Bomb Squad Captain."

### 2:50–3:00 · Close
**Show:** the menu, or the design doc.
**Say:**
> "Built in Godot. All sound is synthesised in code, and everything hardware-specific is in one config file, so it's ready to put on the real display. The first thing I'd test with kids: can they find a mine by sound alone in under a minute? Thanks!"
