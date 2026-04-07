#!/usr/bin/env bash
#
# Generate .pyi type stubs for the 3D Slicer Python environment.
# Gives PyLance (VS Code) autocomplete for slicer.vtkMRMLNode, vtk.*, etc.
#
# Prerequisites:
#   - A completed Slicer superbuild
#   - xvfb-run (for PythonQt stubs): apt install xvfb
#
# Usage:
#   ./generate_all_stubs.sh <superbuild-dir> <output-dir>
#
# Example:
#   ./generate_all_stubs.sh ~/slicer-superbuild-v5.10 ~/slicer-stubs

set -euo pipefail

SUPERBUILD="$(cd "${1:?Usage: $0 <superbuild-dir> <output-dir>}" && pwd)"
OUTPUT_DIR="$(cd "${2:?Usage: $0 <superbuild-dir> <output-dir>}" && pwd)"

SLICER_BUILD="$SUPERBUILD/Slicer-build"
PYTHON_SLICER="$SUPERBUILD/python-install/bin/PythonSlicer"

if [ ! -x "$PYTHON_SLICER" ]; then
    echo "ERROR: PythonSlicer not found at $PYTHON_SLICER"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ── Step 1: Install mypy ──────────────────────────────────────────────
echo "==> Step 1: Ensuring mypy is installed in Slicer Python..."
"$PYTHON_SLICER" -m pip install --quiet mypy

# ── Step 2: Discover all VTK-wrapped .so modules ─────────────────────
echo "==> Step 2: Discovering VTK-wrapped modules..."
VTK_MODULES=$(find "$SLICER_BUILD/bin" "$SLICER_BUILD/lib" -name '*Python.so' 2>/dev/null \
    | sed 's/.*\///; s/\.so$//' | sort -u)
VTK_MODULE_COUNT=$(echo "$VTK_MODULES" | wc -l)
echo "    Found $VTK_MODULE_COUNT VTK-wrapped modules"

# ── Step 3: Generate stubs for VTK-wrapped modules (stubgen) ─────────
echo "==> Step 3: Generating stubs for VTK-wrapped modules..."
MODULE_ARGS=""
for m in $VTK_MODULES; do
    MODULE_ARGS="$MODULE_ARGS '-m', '$m',"
done

cd "$SLICER_BUILD"
LD_LIBRARY_PATH="$(pwd)/bin:$(pwd)/lib/Slicer-5.10/qt-loadable-modules:$SUPERBUILD/python-install/lib:${LD_LIBRARY_PATH:-}" \
PYTHONPATH="$(pwd)/bin:$(pwd)/lib/Slicer-5.10/qt-loadable-modules:$(pwd)/bin/Python:${PYTHONPATH:-}" \
"$PYTHON_SLICER" -c "
import sys
sys.argv = ['stubgen', '--inspect-mode', $MODULE_ARGS '-o', '$OUTPUT_DIR']
from mypy.stubgen import main
main()
"

# ── Step 4: Generate stubs for slicer package and re-export modules ──
echo "==> Step 4: Generating stubs for slicer package..."
LD_LIBRARY_PATH="$(pwd)/bin:$(pwd)/lib/Slicer-5.10/qt-loadable-modules:$SUPERBUILD/python-install/lib:${LD_LIBRARY_PATH:-}" \
PYTHONPATH="$(pwd)/bin:$(pwd)/lib/Slicer-5.10/qt-loadable-modules:$(pwd)/bin/Python:${PYTHONPATH:-}" \
"$PYTHON_SLICER" -c "
import sys
sys.argv = ['stubgen', '--inspect-mode',
    '-m', 'mrml', '-m', 'vtkAddon', '-m', 'vtkSegmentationCore',
    '-m', 'slicer', '-m', 'slicer.util', '-m', 'slicer.cli',
    '-m', 'slicer.i18n', '-m', 'slicer.testing', '-m', 'slicer.kits',
    '-m', 'slicer.logic', '-m', 'slicer.ScriptedLoadableModule',
    '-o', '$OUTPUT_DIR']
from mypy.stubgen import main
main()
"

# ── Step 5: Generate stubs for VTK modules (vtkmodules.*) ────────────
echo "==> Step 5: Generating stubs for VTK modules..."
LD_LIBRARY_PATH="$(pwd)/bin:$(pwd)/lib/Slicer-5.10/qt-loadable-modules:$SUPERBUILD/python-install/lib:${LD_LIBRARY_PATH:-}" \
PYTHONPATH="$(pwd)/bin:$(pwd)/lib/Slicer-5.10/qt-loadable-modules:$(pwd)/bin/Python:${PYTHONPATH:-}" \
"$PYTHON_SLICER" -c "
import sys, os
import vtkmodules
vtk_dir = os.path.dirname(vtkmodules.__file__)
so_modules = sorted(set(f.split('.')[0] for f in os.listdir(vtk_dir) if f.endswith('.so')))
args = ['stubgen', '--inspect-mode']
for m in so_modules:
    args.extend(['-m', f'vtkmodules.{m}'])
args.extend(['-m', 'vtk', '-o', '$OUTPUT_DIR'])
sys.argv = args
print(f'    Generating stubs for {len(so_modules)} VTK submodules...')
from mypy.stubgen import main
main()
"

# ── Step 6: Fix wildcard re-exports (stubgen doesn't resolve them) ───
echo "==> Step 6: Fixing wildcard re-exports in mrml.pyi and slicer/__init__.pyi..."
LD_LIBRARY_PATH="$(pwd)/bin:$(pwd)/lib/Slicer-5.10/qt-loadable-modules:$SUPERBUILD/python-install/lib:${LD_LIBRARY_PATH:-}" \
PYTHONPATH="$(pwd)/bin:$(pwd)/lib/Slicer-5.10/qt-loadable-modules:$(pwd)/bin/Python:${PYTHONPATH:-}" \
"$PYTHON_SLICER" -c "
import importlib, os

OUTPUT_DIR = '$OUTPUT_DIR'

# === Fix mrml.pyi ===
import MRMLCorePython, MRMLCLIPython, MRMLDisplayableManagerPython, MRMLLogicPython
sources = {
    'MRMLCorePython': set(dir(MRMLCorePython)),
    'MRMLCLIPython': set(dir(MRMLCLIPython)),
    'MRMLDisplayableManagerPython': set(dir(MRMLDisplayableManagerPython)),
    'MRMLLogicPython': set(dir(MRMLLogicPython)),
}
import mrml
names = sorted(n for n in dir(mrml) if not n.startswith('_'))
lines = []
for name in names:
    for mod, attrs in sources.items():
        if name in attrs:
            lines.append(f'from {mod} import {name} as {name}')
            break
with open(os.path.join(OUTPUT_DIR, 'mrml.pyi'), 'w') as f:
    f.write('\n'.join(lines) + '\n')
print(f'    mrml.pyi: {len(lines)} re-exports')

# === Fix slicer/__init__.pyi ===
# Collect all VTK-wrapped module exports
so_modules = [
    'MRMLCorePython', 'MRMLCLIPython', 'MRMLDisplayableManagerPython', 'MRMLLogicPython',
    'vtkAddonPython', 'vtkSegmentationCorePython', 'SlicerBaseLogicPython',
    'vtkITKPython', 'vtkTeemPython',
]
# Add loadable module .so files
import glob
for so_path in sorted(glob.glob(os.path.join('$SLICER_BUILD', 'lib', 'Slicer-*', 'qt-loadable-modules', '*Python.so'))):
    mod_name = os.path.basename(so_path).replace('.so', '')
    if mod_name not in so_modules:
        so_modules.append(mod_name)

source_map = {}
for mod_name in so_modules:
    try:
        mod = importlib.import_module(mod_name)
        for attr in dir(mod):
            if not attr.startswith('_'):
                source_map.setdefault(attr, mod_name)
    except ImportError:
        pass

slicer_lines = []
slicer_lines.append('from . import cli as cli, i18n as i18n, kits as kits, logic as logic, testing as testing, util as util')
slicer_lines.append('from .ScriptedLoadableModule import ScriptedLoadableModule as ScriptedLoadableModule, ScriptedLoadableModuleWidget as ScriptedLoadableModuleWidget, ScriptedLoadableModuleLogic as ScriptedLoadableModuleLogic, ScriptedLoadableModuleTest as ScriptedLoadableModuleTest')
slicer_lines.append('')
for name in sorted(source_map.keys()):
    slicer_lines.append(f'from {source_map[name]} import {name} as {name}')
slicer_lines.append('')
slicer_lines.append('# Dynamic attributes set at runtime by SlicerApp')
slicer_lines.append('from typing import Any')
slicer_lines.append('app: Any')
slicer_lines.append('mrmlScene: MRMLCorePython.vtkMRMLScene')
slicer_lines.append('modules: Any')
slicer_lines.append('moduleNames: Any')

with open(os.path.join(OUTPUT_DIR, 'slicer', '__init__.pyi'), 'w') as f:
    f.write('\n'.join(slicer_lines) + '\n')
print(f'    slicer/__init__.pyi: {len(source_map)} VTK re-exports')
"

# ── Step 7: Generate PythonQt stubs (requires full Slicer + xvfb) ────
SLICER_EXE="$SLICER_BUILD/Slicer"
if command -v xvfb-run &>/dev/null && [ -x "$SLICER_EXE" ]; then
    echo "==> Step 7: Generating PythonQt stubs (via xvfb-run + Slicer)..."
    SLICER_STUBS_OUTPUT_DIR="$OUTPUT_DIR" xvfb-run "$SLICER_EXE" --no-splash --no-main-window \
        --python-script "$OUTPUT_DIR/generate_pythonqt_stubs.py" \
        --exit-after-startup 2>&1 | grep '^\s*OK\|^\s*SKIP\|^Done' || true

    # Add PythonQt re-exports to slicer/__init__.pyi
    echo "    Adding PythonQt re-exports to slicer/__init__.pyi..."
    xvfb-run "$SLICER_EXE" --no-splash --no-main-window \
        --python-script /dev/stdin --exit-after-startup 2>/dev/null <<PYEOF
import importlib, os, glob
OUTPUT_DIR = "$OUTPUT_DIR"
# Discover all PythonQt modules that had stubs generated
pythonqt_modules = sorted(
    os.path.basename(p).replace(".pyi", "")
    for p in glob.glob(os.path.join(OUTPUT_DIR, "*PythonQt.pyi"))
)
stub_path = os.path.join(OUTPUT_DIR, "slicer", "__init__.pyi")
with open(stub_path) as f:
    existing = f.read()
source_map = {}
for mod_name in pythonqt_modules:
    try:
        mod = importlib.import_module(mod_name)
        for attr in dir(mod):
            if not attr.startswith("_"):
                source_map.setdefault(attr, mod_name)
    except ImportError as e:
        print(f"Skipping {mod_name}: {e}")
new_lines = []
for name in sorted(source_map.keys()):
    line = f"from {source_map[name]} import {name} as {name}"
    if line not in existing:
        new_lines.append(line)
parts = existing.split("# Dynamic attributes set at runtime by SlicerApp")
with open(stub_path, "w") as f:
    f.write(parts[0])
    for line in new_lines:
        f.write(line + "\n")
    f.write("\n# Dynamic attributes set at runtime by SlicerApp")
    f.write(parts[1])
print(f"    Added {len(new_lines)} PythonQt re-exports from {len(pythonqt_modules)} modules")
PYEOF
else
    echo "==> Step 7: SKIPPED (xvfb-run or Slicer not found)"
    echo "    Install xvfb (apt install xvfb) and ensure Slicer is built to generate PythonQt stubs"
fi

# ── Step 8: Fix C++ type leaks in stubgen output ────────────────────
# stubgen sometimes emits duplicate overloads with raw C++ signatures
# (e.g. "vtkPolyData*polyData" instead of "polyData: vtkPolyData").
# The valid Python-typed overload is always present, so remove the bad ones.
echo "==> Step 8: Removing overloads with C++ type syntax..."
"$PYTHON_SLICER" -c "
import ast, glob, os

def fix_stub(path):
    with open(path) as f:
        lines = f.readlines()
    fixes = 0
    for _attempt in range(50):
        try:
            ast.parse(''.join(lines))
            break
        except SyntaxError as e:
            # Search backwards from error line for @overload
            start = e.lineno - 2  # 0-indexed, start searching before error
            while start >= 0 and '@overload' not in lines[start]:
                start -= 1
            if start < 0:
                start = e.lineno - 1
            # Search forward from error line for '...' (end of stub def)
            end = e.lineno - 1
            while end < len(lines) and '...' not in lines[end]:
                end += 1
            end += 1  # include the line with '...'
            del lines[start:end]
            fixes += 1
    else:
        print(f'    WARN: could not fully fix {os.path.basename(path)}')
    if fixes:
        with open(path, 'w') as f:
            f.writelines(lines)
    return fixes

total = 0
for path in sorted(glob.glob(os.path.join('$OUTPUT_DIR', '**', '*.pyi'), recursive=True)):
    n = fix_stub(path)
    if n:
        total += n
print(f'    Removed {total} bad overloads across generated stubs')
"

# ── Done ──────────────────────────────────────────────────────────────
echo ""
echo "=== Stubs generated at $OUTPUT_DIR ==="
echo "    .pyi files: $(find "$OUTPUT_DIR" -name '*.pyi' | wc -l)"
echo "    Total size: $(du -sh "$OUTPUT_DIR" | cut -f1)"
echo ""
echo "Add to your VS Code .vscode/settings.json:"
echo ""
echo '  {'
echo "    \"python.analysis.stubPath\": \"$OUTPUT_DIR\","
echo '    "python.analysis.extraPaths": ['
echo "      \"$SLICER_BUILD/bin/Python\","
echo "      \"$SLICER_BUILD/lib/Slicer-5.10/qt-scripted-modules\","
echo "      \"$SLICER_BUILD/lib/Slicer-5.10/qt-loadable-modules/Python\","
echo "      \"$SUPERBUILD/python-install/lib/python3.12/site-packages\","
echo "      \"$SUPERBUILD/VTK-build/lib/python3.12/site-packages\","
echo "      \"$SUPERBUILD/CTK-build/CTK-build/bin/Python\""
echo '    ],'
echo '    "python.analysis.diagnosticSeverityOverrides": {'
echo '      "reportMissingModuleSource": "none"'
echo '    }'
echo '  }'
echo ""
echo "Note: python.defaultInterpreterPath is intentionally omitted."
echo "The superbuild Python cannot run standalone (needs LD_LIBRARY_PATH"
echo "for libpython3.12.so), so VS Code can't use it. PyLance uses"
echo "stubPath and extraPaths for autocomplete, not the interpreter."
