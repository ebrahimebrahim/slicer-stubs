"""Generate .pyi stubs for PythonQt-wrapped Slicer modules.

Must be run from within a full Slicer application context:
  xvfb-run ~/slicer-superbuild-v5.10/Slicer-build/Slicer --no-splash --no-main-window \
    --python-script /home/ebrahim/slicer-stubs/generate_pythonqt_stubs.py --exit-after-startup

PythonQt uses PythonQtClassWrapper which mypy's InspectionStubGenerator
doesn't understand. This script parses PythonQt's docstrings to extract
method signatures.
"""

import importlib
import os
import re

OUTPUT_DIR = "/home/ebrahim/slicer-stubs"

PYTHONQT_MODULES = [
    "qMRMLWidgetsPythonQt",
    "qSlicerBaseQTAppPythonQt",
    "qSlicerBaseQTCLIPythonQt",
    "qSlicerBaseQTCorePythonQt",
    "qSlicerBaseQTGUIPythonQt",
    "qSlicerColorsModuleWidgetsPythonQt",
    "qSlicerColorsSubjectHierarchyPluginsPythonQt",
    "qSlicerDICOMLibModuleWidgetsPythonQt",
    "qSlicerDICOMLibSubjectHierarchyPluginsPythonQt",
    "qSlicerDynamicModelerSubjectHierarchyPluginsPythonQt",
    "qSlicerMarkupsModuleWidgetsPythonQt",
    "qSlicerMarkupsSubjectHierarchyPluginsPythonQt",
    "qSlicerModelsModuleWidgetsPythonQt",
    "qSlicerModelsSubjectHierarchyPluginsPythonQt",
    "qSlicerPlotsModuleWidgetsPythonQt",
    "qSlicerPlotsSubjectHierarchyPluginsPythonQt",
    "qSlicerSegmentationsEditorEffectsPythonQt",
    "qSlicerSegmentationsModuleWidgetsPythonQt",
    "qSlicerSegmentationsSubjectHierarchyPluginsPythonQt",
    "qSlicerSequencesModuleWidgetsPythonQt",
    "qSlicerSubjectHierarchyModuleWidgetsPythonQt",
    "qSlicerTablesModuleWidgetsPythonQt",
    "qSlicerTablesSubjectHierarchyPluginsPythonQt",
    "qSlicerTemplateKeyModuleWidgetsPythonQt",
    "qSlicerTerminologiesModuleWidgetsPythonQt",
    "qSlicerTextsModuleWidgetsPythonQt",
    "qSlicerTextsSubjectHierarchyPluginsPythonQt",
    "qSlicerTransformsModuleWidgetsPythonQt",
    "qSlicerTransformsSubjectHierarchyPluginsPythonQt",
    "qSlicerUnitsModuleWidgetsPythonQt",
    "qSlicerVolumeRenderingModuleWidgetsPythonQt",
    "qSlicerVolumeRenderingSubjectHierarchyPluginsPythonQt",
    "qSlicerVolumesModuleWidgetsPythonQt",
    "qSlicerVolumesSubjectHierarchyPluginsPythonQt",
]

# Map PythonQt type names to Python type annotations
TYPE_MAP = {
    "int": "int",
    "float": "float",
    "double": "float",
    "bool": "bool",
    "str": "str",
    "bytes": "bytes",
    "tuple": "tuple",
    "list": "list",
    "dict": "dict",
    "object": "object",
    "None": "None",
}


def map_return_type(type_str):
    """Convert PythonQt return type string to a Python annotation."""
    if not type_str:
        return "None"
    type_str = type_str.strip()
    if type_str in TYPE_MAP:
        return TYPE_MAP[type_str]
    # PythonQt.QtGui.QWidget -> Any (we could be more precise but it's fine)
    if "PythonQt." in type_str:
        # Extract the class name
        return "'%s'" % type_str.split(".")[-1]
    return "'%s'" % type_str


def parse_doc_signature(doc):
    """Parse 'X.method(arg1, arg2) -> RetType' from PythonQt docstring."""
    if not doc:
        return None, None, None
    # Match: X.name(args) or X.name(args) -> type
    match = re.match(r"X\.(\w+)\(([^)]*)\)(?:\s*->\s*(.+))?", doc.strip())
    if not match:
        return None, None, None
    name = match.group(1)
    args_str = match.group(2).strip()
    ret_type = match.group(3)
    args = [a.strip() for a in args_str.split(",") if a.strip()] if args_str else []
    return name, args, ret_type


def generate_class_stub(cls_name, cls):
    """Generate stub lines for a PythonQt class."""
    lines = []
    lines.append(f"class {cls_name}:")

    has_content = False

    # Collect class-level constants (enums, etc.)
    for attr_name in sorted(dir(cls)):
        if attr_name.startswith("_"):
            continue
        try:
            attr = getattr(cls, attr_name)
        except Exception:
            continue
        if isinstance(attr, int) and attr_name[0].isupper():
            lines.append(f"    {attr_name}: int")
            has_content = True

    # Collect methods
    for attr_name in sorted(dir(cls)):
        if attr_name.startswith("_"):
            continue
        try:
            attr = getattr(cls, attr_name)
        except Exception:
            continue

        type_name = type(attr).__name__

        if type_name in ("builtin_qt_slot", "method_descriptor", "builtin_function_or_method"):
            doc = getattr(attr, "__doc__", "")
            _, args, ret_type = parse_doc_signature(doc)
            if args is not None:
                params = ", ".join(args)
                ret = map_return_type(ret_type)
                lines.append(f"    def {attr_name}(self, {params}) -> {ret}: ..." if params else f"    def {attr_name}(self) -> {ret}: ...")
            else:
                lines.append(f"    def {attr_name}(self, *args, **kwargs): ...")
            has_content = True
        elif type_name == "property":
            lines.append(f"    {attr_name}: Any")
            has_content = True

    if not has_content:
        lines.append("    ...")

    return lines


def generate_module_stub(module_name):
    """Generate a .pyi stub for a PythonQt module."""
    try:
        mod = importlib.import_module(module_name)
    except ImportError as e:
        print(f"  SKIP {module_name}: {e}")
        return False

    lines = ["from typing import Any", ""]

    attrs = sorted([a for a in dir(mod) if not a.startswith("_")])

    for attr_name in attrs:
        try:
            attr = getattr(mod, attr_name)
        except Exception:
            continue

        type_name = type(attr).__name__
        if type_name == "PythonQtClassWrapper":
            class_lines = generate_class_stub(attr_name, attr)
            lines.extend(class_lines)
            lines.append("")
        elif isinstance(attr, int):
            lines.append(f"{attr_name}: int")
        elif isinstance(attr, str):
            lines.append(f"{attr_name}: str")
        elif isinstance(attr, float):
            lines.append(f"{attr_name}: float")

    out_path = os.path.join(OUTPUT_DIR, f"{module_name}.pyi")
    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")

    class_count = sum(1 for line in lines if line.startswith("class "))
    print(f"  OK   {module_name} ({class_count} classes)")
    return True


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    success = 0
    fail = 0
    for mod_name in PYTHONQT_MODULES:
        if generate_module_stub(mod_name):
            success += 1
        else:
            fail += 1
    print(f"\nDone: {success} generated, {fail} skipped")


if __name__ == "__main__":
    main()
