"""Embed the shared coordinator so the distributed controller stays standalone."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
START = "-- BEGIN NO FALL COORDINATOR\n"
END = "-- END NO FALL COORDINATOR\n"
source = (ROOT / "FLY-SSJ3.lua").read_text()
module = (ROOT / "runtime/NoFallDamageLease.luau").read_text()
block = START + "local createNoFallLease = (function()\n" + module + "end)()\n" + END
if START in source:
    before, rest = source.split(START, 1)
    _, after = rest.split(END, 1)
    source = before + block + after
else:
    source = source.replace("local CONFIG = {", block + "\nlocal CONFIG = {", 1)
(ROOT / "FLY-SSJ3.lua").write_text(source)
