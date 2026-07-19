#!/usr/bin/env bash
# desktop/hyprland kitty — Windows/PowerShell look: pure black bg + blinking beam cursor,
# on the Atlas B&W identity (JetBrainsMono, greyscale ramp, the one red).
KITTY="$ATLAS_ROOT/modules/desktop/hyprland/config/kitty/kitty.conf"

assert_status "kitty background is pure black" 0 \
  bash -c "grep -qxE 'background +#000000' \"$KITTY\""
assert_status "kitty has no near-black grey left" 1 \
  bash -c "grep -q '#070707' \"$KITTY\""
assert_status "kitty cursor is a beam, not a block" 0 \
  bash -c "grep -qxE 'cursor_shape +beam' \"$KITTY\""
assert_status "kitty cursor blinks every 0.5s" 0 \
  bash -c "grep -qxE 'cursor_blink_interval +0[.]5' \"$KITTY\""
assert_status "kitty cursor never stops blinking" 0 \
  bash -c "grep -qxE 'cursor_stop_blinking_after +0' \"$KITTY\""
assert_status "kitty keeps JetBrainsMono" 0 \
  bash -c "grep -q 'JetBrainsMono' \"$KITTY\""
assert_status "kitty keeps the single Atlas red" 0 \
  bash -c "grep -q 'E5484D' \"$KITTY\""
