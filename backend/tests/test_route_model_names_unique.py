"""A route file that defines the same request model twice silently replaces the first one (a desk route then
answered 422). Every top-level class name in a route module must be unique."""

import ast
from collections import Counter
from pathlib import Path

ROUTES = Path(__file__).resolve().parents[1] / "app" / "api" / "routes"


def test_no_route_module_defines_a_class_twice():
    bad = {}
    for path in sorted(ROUTES.glob("*.py")):
        names = [n.name for n in ast.parse(path.read_text(encoding="utf-8")).body if isinstance(n, ast.ClassDef)]
        dupes = [name for name, count in Counter(names).items() if count > 1]
        if dupes:
            bad[path.name] = dupes
    assert not bad, bad
