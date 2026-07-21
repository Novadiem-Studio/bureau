# Fowler Smell Baseline

> Canon module. Load this file for build-diff reviews when applying the Standards axis.

## Purpose

The Standards axis reviews the diff against the target repo's documented standards first. When
those docs are silent, this baseline gives the reviewer a small fixed vocabulary for common
design smells. These are heuristics, not automatic violations: cite the hunk, explain the
maintenance cost, and suppress the smell when a repo convention explicitly allows the shape or
tooling already enforces it.

## The 12-Smell Floor

1. **Mysterious Name** - a name hides what the value, function, or type actually means.
2. **Duplicated Code** - the same logic shape appears in more than one changed place.
3. **Feature Envy** - behavior reaches into another object's data more than its own.
4. **Data Clumps** - the same group of fields or parameters keeps travelling together.
5. **Primitive Obsession** - a string, number, or boolean stands in for a domain concept.
6. **Repeated Switches** - the same branch cascade on the same concept recurs.
7. **Shotgun Surgery** - one logical change requires scattered edits across many files.
8. **Divergent Change** - one module changes for several unrelated reasons.
9. **Speculative Generality** - abstraction or hooks are added before the spec needs them.
10. **Message Chains** - callers navigate through a long object chain they should not know.
11. **Middle Man** - a layer mostly delegates without adding policy or useful boundary value.
12. **Refused Bequest** - an inheritance/implementation relationship is mostly ignored or
    worked around.

Use the smell name in findings as `possible <Smell Name>` unless the project standard makes it
a hard rule. The fix is usually to rename, remove duplication, move behavior to the owning
data, introduce a domain type, collapse premature abstraction, or split the change so modules
change for one reason.
