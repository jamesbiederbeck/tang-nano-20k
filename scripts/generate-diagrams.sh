#!/usr/bin/env bash
# Make an RTL schematic SVG for a project's top module: yosys -> JSON netlist -> netlistsvg.
# Only worth it for small leaf modules (blink). State machines and big tops come out as unreadable gate soup;
# those get hand-drawn overviews from scripts/draw_diagrams.py instead.
# Output: docs/diagrams/<project-folder-name>-rtl.svg. Run from anywhere; needs the APIO oss-cad-suite and node/npx.
# Usage: scripts/generate-diagrams.sh project-dir [project-dir ...]     e.g. scripts/generate-diagrams.sh projects/blink
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.apio/packages/oss-cad-suite/bin:$PATH"
OUT="$ROOT/docs/diagrams"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

# Gowin primitives (rPLL, CLKDIV, OSER10, TLVDS_OBUF, ...) as black boxes with their real ports.
GOWIN_DIR="$(yosys-config --datdir)/gowin"

# Gowin's cells_sim.v holds behavioural models (rPLL, OSER10, TLVDS_OBUF, ...) that the JSON exporter chokes on.
# Keep only each module's name, ports and directions as an empty black box.
python3 -I - "$GOWIN_DIR/cells_sim.v" "$WORK/gowin_stubs.v" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
out = []
for m in re.finditer(r"^module\s+(\w+)\s*(?:#\s*\(.*?\)\s*)?\((.*?)\)\s*;(.*?)^endmodule", src, re.S | re.M):
    name, header, body = m.groups()
    if re.search(r"\b(input|output|inout)\b", header):           # ANSI-style port list
        out.append(f"(* blackbox *) module {name} ({header}); endmodule")
        continue
    params = re.findall(r"^\s*(parameter\b[^;]*);", body, re.M)
    decls = re.findall(r"^\s*(?:\(\*.*?\*\)\s*)?((?:input|output|inout)\b[^;]*);", body, re.M)
    out.append(f"(* blackbox *) module {name} ({header});\n" + "\n".join([x + ";" for x in params] + [d + ";" for d in decls]) + "\nendmodule")
open(sys.argv[2], "w").write("\n".join(out) + "\n")
PY

render() {
    local dir="$1" top name sources=()
    name="$(basename "$dir")"
    top="$(sed -n 's/^[[:space:]]*top-module[[:space:]]*=[[:space:]]*//p' "$dir/apio.ini" | tr -d '[:space:]')"
    [ -n "$top" ] || { echo "skip $dir: no top-module in apio.ini"; return 0; }
    while IFS= read -r f; do sources+=("$f"); done < <(find "$dir" -maxdepth 1 -name '*.v' ! -name '*_tb.v' | sort)
    [ ${#sources[@]} -gt 0 ] || { echo "skip $dir: no sources"; return 0; }

    echo "== $name (top module $top)"
    yosys -q -p "
        read_verilog $WORK/gowin_stubs.v;
        read_verilog -lib $GOWIN_DIR/cells_xtra_gw2a.v;
        read_verilog -DSYNTHESIZE ${sources[*]};
        hierarchy -check -top $top;
        proc; opt_clean -purge;
        write_json $WORK/$name.json
    "
    # netlistsvg rejects the library black boxes (some have inout ports); instances keep their own port directions.
    python3 -I - "$WORK/$name.json" "$top" <<'PY'
import json, sys
path, top = sys.argv[1:3]
d = json.load(open(path))
d["modules"] = {k: v for k, v in d["modules"].items()
                if k == top or "blackbox" not in v.get("attributes", {})}
json.dump(d, open(path, "w"))
PY
    npx --yes netlistsvg "$WORK/$name.json" -o "$WORK/$name.svg"

    # GitHub shows an SVG in an <img>, so it does not inherit the page theme: give it its own white background.
    sed -i '0,/<svg[^>]*>/s//&<rect width="100%" height="100%" fill="#ffffff"\/>/' "$WORK/$name.svg"
    cp "$WORK/$name.svg" "$OUT/$name-rtl.svg"
    echo "   wrote docs/diagrams/$name-rtl.svg"
}

[ $# -gt 0 ] || { echo "usage: $0 project-dir [project-dir ...]"; exit 1; }
for d in "$@"; do render "$d"; done
