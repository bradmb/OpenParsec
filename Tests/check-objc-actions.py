"""Catch Swift @objc actions that shadow NSObject memory-management selectors."""
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent
reserved = {"release", "retain", "autorelease", "dealloc", "retainCount"}
actions = re.compile(r"@objc(?:\s*\(([^)]*)\))?\s+(?:(?:private|fileprivate|public|internal|final|override|dynamic)\s+)*func\s+(\w+)\s*\(([^)]*)\)")


def collisions(source):
    result = []
    for match in actions.finditer(source):
        explicit, name, parameters = match.groups()
        selector = explicit.strip() if explicit else name + (":" if parameters.strip() else "")
        if selector in reserved:
            result.append(selector)
    return result


assert collisions("@objc private func release() {}") == ["release"]
assert collisions("@objc(release) private func onKeyUp() {}") == ["release"]
assert not collisions("@objc private func handleKeyTouchEnded() {}")
assert not collisions("func release(_ code: UInt32) {}")
for path in (root / "OpenParsec").glob("*.swift"):
    bad = collisions(path.read_text())
    assert not bad, f"{path.name}: unsafe Objective-C action selectors: {bad}"
print("Passed Objective-C action-selector collision checks.")
