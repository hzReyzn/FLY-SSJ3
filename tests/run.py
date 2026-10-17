"""Deterministic controller tests, not a Roblox physics/rendering substitute."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
luau = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path("luau")
source = (root / "FLY-SSJ3.lua").read_text()
module = (root / "runtime/NoFallDamageLease.luau").read_text()
assert "local createNoFallLease = (function()\n" + module + "end)()" in source, "Rebuild the coordinator with tools/build.py"
compiler = luau.with_name("luau-compile")
if compiler.is_file():
    subprocess.run([str(compiler), str(root / "FLY-SSJ3.lua")], check=True, stdout=subprocess.DEVNULL)
for forbidden in ("loadstring", "HttpGet", "setclipboard", 'make("Sound"', 'make("Animator"', "BodyVelocity", "BodyGyro"):
    assert forbidden not in source, forbidden
generated = root / "tests" / "_generated.luau"
try:
    generated.write_text("local source=[====[" + source + "]====]\nrequire('./behavior')(source)\n")
    subprocess.run([str(luau), str(generated)], check=True)
finally:
    generated.unlink(missing_ok=True)
