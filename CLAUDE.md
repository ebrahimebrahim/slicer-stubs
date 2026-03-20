# slicer-stubs

Type stubs (`.pyi` files) for 3D Slicer's Python environment, enabling PyLance
autocomplete in VS Code for VTK-wrapped C++ classes (`slicer.vtkMRMLNode`, `vtk.vtkImageData`, etc.)
and PythonQt-wrapped Qt widgets (`qMRMLNodeComboBox`, etc.).

## What's here

- `generate_all_stubs.sh` — Main script. Generates all stubs from a Slicer superbuild.
- `generate_pythonqt_stubs.py` — Helper called by the main script (step 7). Custom stub
  generator for PythonQt modules, which mypy's `InspectionStubGenerator` can't handle because
  PythonQt uses `PythonQtClassWrapper` instead of regular Python classes.
- `*.pyi`, `slicer/`, `vtkmodules/` — Generated output (git-ignored). ~12 MB covering ~210 modules.

## Regenerating stubs

Run after each Slicer superbuild rebuild (new/changed C++ classes won't appear until you regenerate):

```bash
./generate_all_stubs.sh <superbuild-dir> <output-dir>
# Example:
./generate_all_stubs.sh ~/slicer-superbuild-v5.10 ~/slicer-stubs
```

Prerequisites:
- A completed Slicer superbuild
- `xvfb-run` for PythonQt stubs: `apt install xvfb`

The script installs `mypy` into Slicer's bundled Python if not already present.

## How it works

1. **VTK-wrapped modules** (54 `.so` files like `MRMLCorePython.so`): Uses `mypy stubgen --inspect-mode`
   called from within `PythonSlicer` so the `.so` modules can be imported and introspected.
2. **VTK itself** (124 `vtkmodules/*.so`): Same approach.
3. **Wildcard re-export fixup**: `stubgen` doesn't resolve `from MRMLCorePython import *` chains,
   so a post-processing step writes explicit re-exports into `mrml.pyi` and `slicer/__init__.pyi`.
4. **PythonQt modules** (34 `*PythonQt.so`): These crash outside a running Slicer app, so they're
   generated via `xvfb-run Slicer --python-script generate_pythonqt_stubs.py`. The custom generator
   parses PythonQt's `X.method(args) -> type` docstrings.

## VS Code setup

Add to `.vscode/settings.json` in your Slicer source or workspace:

```json
{
  "python.analysis.stubPath": "<output-dir>",
  "python.analysis.extraPaths": [
    "<superbuild>/Slicer-build/bin/Python",
    "<superbuild>/Slicer-build/lib/Slicer-5.10/qt-scripted-modules",
    "<superbuild>/Slicer-build/lib/Slicer-5.10/qt-loadable-modules/Python",
    "<superbuild>/python-install/lib/python3.12/site-packages",
    "<superbuild>/VTK-build/lib/python3.12/site-packages",
    "<superbuild>/CTK-build/CTK-build/bin/Python"
  ]
}
```

### Interpreter path (optional)

You can omit `python.defaultInterpreterPath` or point it at your system Python
(`/usr/bin/python3`). The superbuild's Python (`python-install/bin/python` and
`PythonSlicer`) cannot run standalone — both need `LD_LIBRARY_PATH` set to find
`libpython3.12.so`, so VS Code's Python extension can't invoke them and will
show a "Select Interpreter" warning in the status bar.

This doesn't affect autocomplete: **PyLance uses `stubPath` and `extraPaths` for
all type analysis, not the interpreter.** The interpreter setting only matters for
running/debugging scripts via VS Code's play button, which isn't how you run
Slicer Python code anyway.

## Known limitations

- `slicer.app` is typed as `Any` — `qSlicerApplication` lives in `PythonQt.private` and isn't
  directly exported by any wrappable module.
- PythonQt method parameter types are not available (only names from docstrings). Return types
  are available when PythonQt provides them.
- Stubs must be regenerated after C++ changes that add/remove/rename wrapped classes or methods.
