# slicer-stubs

PyLance/VS Code autocomplete for [3D Slicer](https://slicer.org)'s Python API.

Slicer wraps thousands of C++ classes (VTK, MRML, Qt widgets) into Python via
VTK wrapping and PythonQt. These are `.so` extension modules with no static type
information, so editors can't provide autocomplete. This project generates `.pyi`
type stubs by introspecting a live Slicer build.

**Before:**
```python
slicer.vtkMRMLScalarVolumeNode  # red squiggly, no autocomplete
```

**After:**
```python
slicer.vtkMRMLScalarVolumeNode  # recognized, with method signatures
```

## Quick start

```bash
# Generate stubs (takes ~2 minutes)
./generate_all_stubs.sh <superbuild-dir> .
```

The script prints VS Code settings to copy into your project's
`.vscode/settings.json` for PyLance autocomplete.

You do **not** need to set `python.defaultInterpreterPath` — the superbuild's
Python can't run standalone (it needs `LD_LIBRARY_PATH` for `libpython3.12.so`).
PyLance uses `stubPath` and `extraPaths` for autocomplete, not the interpreter.

## Prerequisites

- A completed **3D Slicer superbuild** (the stubs are generated from your build)
- **Linux** (see [Platform support](#platform-support))
- `xvfb-run` for Qt widget stubs: `apt install xvfb`
- `mypy` — installed automatically into Slicer's Python by the script

## What you get

| Module group | Count | Examples |
|---|---|---|
| MRML / Slicer core | ~54 | `slicer.vtkMRMLNode`, `slicer.vtkMRMLScene`, `slicer.vtkMRMLScalarVolumeNode` |
| VTK | ~124 | `vtk.vtkImageData`, `vtk.vtkPolyData`, `vtk.vtkMatrix4x4` |
| PythonQt widgets | ~34 | `slicer.qMRMLNodeComboBox`, `slicer.qSlicerWidget` |
| Slicer Python package | 7 | `slicer.util`, `slicer.cli`, `slicer.ScriptedLoadableModule` |

Total: ~12 MB, ~220 stub files.

## Regenerating

Re-run after rebuilding Slicer (new/renamed C++ classes won't appear until you do):

```bash
./generate_all_stubs.sh <superbuild-dir> .
```

## How it works

1. Uses `mypy stubgen --inspect-mode` from within `PythonSlicer` to introspect
   VTK-wrapped `.so` modules at runtime
2. Fixes wildcard re-exports (`from MRMLCorePython import *`) that `stubgen`
   doesn't resolve, so `slicer.vtkMRMLNode` works, not just `MRMLCorePython.vtkMRMLNode`
3. Generates PythonQt widget stubs via `xvfb-run Slicer` with a custom generator
   that parses PythonQt docstrings (mypy can't handle `PythonQtClassWrapper`)

## Platform support

**Linux only.** The scripts assume:
- Shared libraries are `.so` files (not `.dylib` or `.dll`)
- `xvfb-run` is available for headless Qt widget introspection
- `LD_LIBRARY_PATH` is used for library resolution

macOS/Windows would need changes to library discovery, the `xvfb-run` step
(macOS has no Xvfb equivalent — you'd need a real display or skip PythonQt
stubs), and path handling throughout the script.

## Limitations

- **`slicer.app`** is typed as `Any` — `qSlicerApplication` lives in
  `PythonQt.private` and isn't directly importable
- **PythonQt parameter types** are unavailable — only parameter names and return
  types come through (from PythonQt's docstrings)
- **Stubs are a snapshot** of your build — they don't auto-update when you
  rebuild Slicer

## Files

| File | Committed | Purpose |
|---|---|---|
| `generate_all_stubs.sh` | Yes | Main generation script |
| `generate_pythonqt_stubs.py` | Yes | PythonQt stub generator (called by main script) |
| `*.pyi`, `slicer/`, `vtkmodules/` | No (git-ignored) | Generated output |
