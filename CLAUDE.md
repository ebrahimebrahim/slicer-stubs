# slicer-stubs

Type stubs (`.pyi` files) for 3D Slicer's Python environment, enabling PyLance
autocomplete in VS Code for VTK-wrapped C++ classes (`slicer.vtkMRMLNode`, `vtk.vtkImageData`, etc.)
and PythonQt-wrapped Qt widgets (`qMRMLNodeComboBox`, etc.).

## What's here

- `generate_all_stubs.sh` — Main script. Generates all stubs from a Slicer superbuild.
- `generate_pythonqt_stubs.py` — Helper called by the main script (step 7). Custom stub
  generator for PythonQt modules, which mypy's `InspectionStubGenerator` can't handle because
  PythonQt uses `PythonQtClassWrapper` instead of regular Python classes.
- `clean_stubs.sh` — Removes all generated stubs (`*.pyi`, `slicer/`, `vtkmodules/`).
- `*.pyi`, `slicer/`, `vtkmodules/` — Generated output (git-ignored). ~12 MB covering ~220 modules.

## Regenerating stubs

Run after each Slicer superbuild rebuild (new/changed C++ classes won't appear until you regenerate):

```bash
./generate_all_stubs.sh <superbuild-dir> .
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
   parses PythonQt's `X.method(args) -> type` docstrings. Classes from all PythonQt modules
   (including loadable modules) are re-exported into `slicer/__init__.pyi`.
5. **Post-processing**: Removes duplicate overloads where `stubgen` leaks raw C++ type signatures,
   and handles Python keywords used as PythonQt method/parameter names.

## VS Code setup

The generation script prints VS Code settings to copy into your project's
`.vscode/settings.json` for PyLance autocomplete.

`python.defaultInterpreterPath` can be omitted — the superbuild's Python
cannot run standalone (needs `LD_LIBRARY_PATH` for `libpython3.12.so`).
**PyLance uses `stubPath` and `extraPaths` for type analysis, not the interpreter.**

## Known limitations

- `slicer.app` is typed as `Any` — `qSlicerApplication` lives in `PythonQt.private` and isn't
  directly exported by any wrappable module.
- PythonQt method parameter types are not available (only names from docstrings). Return types
  are available when PythonQt provides them.
- Stubs must be regenerated after C++ changes that add/remove/rename wrapped classes or methods.
