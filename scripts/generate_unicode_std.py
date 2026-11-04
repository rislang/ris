#!/usr/bin/env python3
"""Writes the Unicode tables of `src/std/unicode.iyi`.

    python3 scripts/generate_unicode_std.py

The source is `src/unicode/data.cr`, the table of the Unicode Character
Database that `scripts/generate_unicode_data.cr` downloads and writes for the
compatibility library, and `src/unicode/unicode.cr`, which names the UCD
version it was written from. The repository already carries that data, and
both libraries answering from one table is what lets
`bench/std_unicode_exercise.sh` diff them.

Some properties are not in it, because the compatibility library has no
use for them, and are read from the UCD files of the same release, fetched
from unicode.org as `scripts/generate_unicode_data.cr` fetches the rest:

* Cased and Case_Ignorable, which decide the final sigma, from
  `DerivedCoreProperties.txt`. Before they were generated, the module
  approximated them by hand (Ll, Lu and Lt for Cased; every mark and a list
  of eighteen code points for Case_Ignorable) and chose the wrong sigma in
  378 of 20,000 sampled strings.
* Every general category, the punctuation and symbol ones included, from
  `UnicodeData.txt`, and every script from `Scripts.txt`: `std/regex` asks
  for them by name, `\\p{P}` and `\\p{Greek}`, and `data.cr` has neither the
  P and S categories nor any script. The categories `data.cr` does have are
  checked against these code point for code point, so the two sources
  cannot drift apart unnoticed.
* The grapheme cluster properties UAX #29 segments a string by: each code
  point's Grapheme_Cluster_Break from `auxiliary/GraphemeBreakProperty.txt`,
  Extended_Pictographic from `emoji/emoji-data.txt`, and Indic_Conjunct_Break
  from `DerivedCoreProperties.txt`, packed into one value per code point.

What is written, between the `# tables-begin` and `# tables-end` lines of the
module, is one string constant per table: each integer as four characters,
six bits each from `0` up, biased by 2^23, which `RisCodeTable` reads in place.
A string is one static blob in the binary: a program starts with nothing to
decode and threads may read it, and it costs the compiler nothing; an array
literal of thirty thousand integers is thirty thousand stores for LLVM to chew
on and made every program that imports the module several seconds slower to
build.

Every table is sorted by its first column, which is what the module's binary
searches rely on.
"""

from __future__ import annotations

import re
import sys
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DATA = REPO / "src" / "unicode" / "data.cr"
UNICODE = REPO / "src" / "unicode" / "unicode.cr"
MODULE = REPO / "src" / "std" / "unicode.iyi"

BEGIN = "  # tables-begin"
END = "  # tables-end"
WIDTH = 96
UCD_ROOT = "https://www.unicode.org/Public/{version}/ucd/"


def read_tables(text: str) -> dict[str, list[tuple[int, ...]]]:
    """Every `class_getter NAME … do … end` block as a list of `put` rows."""
    tables: dict[str, list[tuple[int, ...]]] = {}
    current: str | None = None
    for line in text.splitlines():
        head = re.match(r"\s*private class_getter (\w+) :", line)
        if head:
            current = head.group(1)
            tables[current] = []
            continue
        if current is None:
            continue
        if re.match(r"\s*end\s*$", line):
            current = None
            continue
        row = re.match(r"\s*put\(data, (.*)\)\s*$", line)
        if not row:
            continue
        values = []
        for item in row.group(1).split(","):
            item = item.strip()
            item = re.sub(r"_(i64|u8|i32)$", "", item)
            if item.startswith("QuickCheckResult::"):
                item = "1" if item.endswith("No") else "2"
            values.append(int(item))
        tables[current].append(tuple(values))
    return tables


def version(text: str) -> str:
    found = re.search(r'VERSION = "([^"]+)"', text)
    if not found:
        sys.exit("no VERSION in " + str(UNICODE))
    return found.group(1)


def derived_core_properties(ucd: str, names: tuple[str, ...]) -> dict[str, set[int]]:
    """The code points of each named property in DerivedCoreProperties.txt of release *ucd*."""
    url = UCD_ROOT.format(version=ucd) + "DerivedCoreProperties.txt"
    with urllib.request.urlopen(url) as response:
        text = response.read().decode("utf-8")
    if not text.startswith(f"# DerivedCoreProperties-{ucd}.txt"):
        sys.exit(f"{url} does not name release {ucd} on its first line")
    properties: dict[str, set[int]] = {name: set() for name in names}
    for line in text.splitlines():
        fields = [field.strip() for field in line.split("#", 1)[0].split(";")]
        if len(fields) < 2 or fields[1] not in properties:
            continue
        span = fields[0].split("..")
        properties[fields[1]].update(range(int(span[0], 16), int(span[-1], 16) + 1))
    for name, points in properties.items():
        if not points:
            sys.exit(f"{url} has no {name} lines")
    return properties


# The general categories in the order the module's category_name answers them,
# which is the order a GENERAL_CATEGORY row's third integer counts in. Cn is
# not among them: an unassigned code point is in no row.
CATEGORIES = (
    "Lu", "Ll", "Lt", "Lm", "Lo", "Mn", "Mc", "Me", "Nd", "Nl", "No",
    "Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po", "Sm", "Sc", "Sk", "So",
    "Zs", "Zl", "Zp", "Cc", "Cf", "Cs", "Co",
)

# Grapheme_Cluster_Break, in the order a GRAPHEME row's low four bits count
# from 1; Other is 0. `std/unicode`'s grapheme segmentation names the same
# numbers.
GRAPHEME_BREAKS = (
    "Prepend", "CR", "LF", "Control", "Extend", "Regional_Indicator", "SpacingMark",
    "L", "V", "T", "LV", "LVT", "ZWJ",
)
# Indic_Conjunct_Break, counting from 1 in a GRAPHEME row's bits 5 and 6;
# None is 0.
CONJUNCT_BREAKS = ("Consonant", "Extend", "Linker")


def property_lines(text: str):
    """Each `XXXX..YYYY ; field ; field # comment` line as (from, to, [fields])."""
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = [part.strip() for part in line.split(";")]
        span = parts[0].split("..")
        yield int(span[0], 16), int(span[-1], 16), parts[1:]


def grapheme_values(ucd: str) -> dict[int, int]:
    """Every code point with a grapheme property, as GRAPHEME packs it."""
    values: dict[int, int] = {}

    def mark(low: int, high: int, bits: int) -> None:
        for point in range(low, high + 1):
            values[point] = values.get(point, 0) | bits

    breaks = fetch(ucd, "auxiliary/GraphemeBreakProperty.txt")
    if not breaks.startswith(f"# GraphemeBreakProperty-{ucd}.txt"):
        sys.exit(f"GraphemeBreakProperty.txt does not name release {ucd} on its first line")
    for low, high, fields in property_lines(breaks):
        mark(low, high, GRAPHEME_BREAKS.index(fields[0]) + 1)
    emoji = fetch(ucd, "emoji/emoji-data.txt")
    if f"# Version: {ucd.rsplit('.', 1)[0]}\n" not in emoji[:2000]:
        sys.exit(f"emoji-data.txt does not name release {ucd} in its header")
    for low, high, fields in property_lines(emoji):
        if fields[0] == "Extended_Pictographic":
            mark(low, high, 16)
    derived = fetch(ucd, "DerivedCoreProperties.txt")
    for low, high, fields in property_lines(derived):
        if fields[0] == "InCB":
            mark(low, high, (CONJUNCT_BREAKS.index(fields[1]) + 1) << 5)
    return values


def fetch(ucd: str, name: str) -> str:
    url = UCD_ROOT.format(version=ucd) + name
    with urllib.request.urlopen(url) as response:
        return response.read().decode("utf-8")


def labelled_runs(points: dict[int, int]) -> list[tuple[int, int, int]]:
    """`{from, to, label}` rows: each maximal run of consecutive code points with one label."""
    rows: list[list[int]] = []
    for point in sorted(points):
        label = points[point]
        if rows and rows[-1][1] == point - 1 and rows[-1][2] == label:
            rows[-1][1] = point
        else:
            rows.append([point, point, label])
    return [tuple(row) for row in rows]


def general_categories(ucd: str) -> dict[int, str]:
    """Every assigned code point's general category, from UnicodeData.txt of release *ucd*.

    The file names no release inside it, so `main` checks the categories
    `data.cr` also has against these, which is what pins the release.
    """
    categories: dict[int, str] = {}
    first = None
    for line in fetch(ucd, "UnicodeData.txt").splitlines():
        fields = line.split(";")
        if len(fields) < 3:
            continue
        point, name, category = int(fields[0], 16), fields[1], fields[2]
        if name.endswith(", First>"):
            first = point
            continue
        start = first if name.endswith(", Last>") and first is not None else point
        first = None
        for each in range(start, point + 1):
            categories[each] = category
    unknown = set(categories.values()) - set(CATEGORIES)
    if unknown:
        sys.exit(f"UnicodeData.txt names categories this module does not: {sorted(unknown)}")
    return categories


def scripts(ucd: str) -> dict[int, str]:
    """Every code point's script, from Scripts.txt of release *ucd*; Unknown is not listed."""
    text = fetch(ucd, "Scripts.txt")
    if not text.startswith(f"# Scripts-{ucd}.txt"):
        sys.exit(f"Scripts.txt does not name release {ucd} on its first line")
    found: dict[int, str] = {}
    for line in text.splitlines():
        fields = [field.strip() for field in line.split("#", 1)[0].split(";")]
        if len(fields) < 2:
            continue
        span = fields[0].split("..")
        for point in range(int(span[0], 16), int(span[-1], 16) + 1):
            found[point] = fields[1]
    if not found:
        sys.exit("Scripts.txt has no script lines")
    return found


def simple_only_foldings(ucd: str) -> list[tuple[int, int]]:
    """The `S` rows of CaseFolding.txt of release *ucd*: simple foldings of code points that also have a full one.

    `data.cr` keeps the full folding of these and drops the simple one, so
    `foldcase` leaves `ẞ` as it is; a case-insensitive match needs the
    simple one, since RE2's `(?i)ß` matches `ẞ`.
    """
    text = fetch(ucd, "CaseFolding.txt")
    if not text.startswith(f"# CaseFolding-{ucd}.txt"):
        sys.exit(f"CaseFolding.txt does not name release {ucd} on its first line")
    rows = []
    for line in text.splitlines():
        fields = [field.strip() for field in line.split("#", 1)[0].split(";")]
        if len(fields) >= 3 and fields[1] == "S":
            rows.append((int(fields[0], 16), int(fields[2], 16)))
    if not rows:
        sys.exit("CaseFolding.txt has no S rows")
    return sorted(rows)


def expand(strided: list[tuple[int, ...]]) -> set[int]:
    """The code points a `{from, to, stride}` table names."""
    points: set[int] = set()
    for start, stop, stride in strided:
        points.update(range(start, stop + 1, stride))
    return points


def runs(points: set[int]) -> list[tuple[int, int, int]]:
    """`{from, to, stride}` rows covering *points*, greedy and longest-first.

    A run of one point has stride 1; two points at any distance form a run
    of that stride, extended while the distance repeats.
    """
    ordered = sorted(points)
    rows: list[tuple[int, int, int]] = []
    index = 0
    while index < len(ordered):
        start = ordered[index]
        if index + 1 == len(ordered):
            rows.append((start, start, 1))
            break
        stride = ordered[index + 1] - start
        stop = ordered[index + 1]
        index += 2
        while index < len(ordered) and ordered[index] - stop == stride:
            stop = ordered[index]
            index += 1
        rows.append((start, stop, stride))
    return rows


def flat(rows: list[tuple[int, ...]]) -> list[int]:
    return [value for row in rows for value in row]


def encode(value: int) -> str:
    """An integer as `RisCodeTable` reads it, escaped for a string literal."""
    biased = value + (1 << 23)
    if not 0 <= biased < (1 << 24):
        sys.exit(f"{value} does not fit a table entry")
    digits = (chr(48 + ((biased >> shift) & 63)) for shift in (18, 12, 6, 0))
    return "".join(digits).replace("\\", "\\\\")


def literal(name: str, comment: str, values: list[int]) -> str:
    lines = []
    line = ""
    for value in values:
        code = encode(value)
        if len(line) + len(code) > WIDTH:
            lines.append(line)
            line = ""
        line += code
    lines.append(line)
    out = [f"  # {comment}"]
    prefix = f"  {name} = "
    pad = " " * len(prefix)
    if len(lines) == 1:
        out.append(f'{prefix}"{lines[0]}"')
    else:
        out.append(f'{prefix}"{lines[0]}" \\')
        for line in lines[1:-1]:
            out.append(f'{pad}"{line}" \\')
        out.append(f'{pad}"{lines[-1]}"')
    return "\n".join(out)


def words(count: str, reader: str, comment: str,
          names: list[str] | tuple[str, ...]) -> str:
    """How many names there are, and a def answering the name at an index:
    each a literal, so nothing is built or stored."""
    out = [f"  # {comment}", f"  {count} = {len(names)}", "",
           f"  private def self.{reader}(index : Int32) : String",
           "    case index"]
    out.extend(f'    when {i} then "{word}"' for i, word in enumerate(names))
    out.extend(['    else ""', "    end", "  end"])
    return "\n".join(out)


def case_orbits(simple: list[tuple[int, ...]], casefold: list[tuple[int, ...]],
                special: list[tuple[int, ...]]) -> dict[int, list[int]]:
    """The simple foldings read backwards: each folded code point to every code
    point that folds to it, itself included, sorted. A code point one table
    folds is not folded again by a later one."""
    orbits: dict[int, set[int]] = {}

    def join(folded: int, point: int) -> None:
        orbits.setdefault(folded, {folded}).add(point)

    folded_simply = {row[0] for row in simple}
    in_casefold = set()
    for point, folded in simple:
        join(folded, point)
    for low, high, delta in casefold:
        for point in range(low, high + 1):
            in_casefold.add(point)
            if point not in folded_simply:
                join(point + delta, point)
    for point, first, second, _third in special:
        if second == 0 and point not in in_casefold and point not in folded_simply:
            join(first, point)
    return {folded: sorted(members) for folded, members in orbits.items()}


def main() -> None:
    tables = read_tables(DATA.read_text(encoding="utf-8"))
    ucd = version(UNICODE.read_text(encoding="utf-8"))
    derived = derived_core_properties(ucd, ("Cased", "Case_Ignorable"))

    def strided(*names: str) -> list[tuple[int, int, int]]:
        points: set[int] = set()
        for name in names:
            points |= expand(tables[name])
        return runs(points)

    def keyed(name: str, width: int) -> list[tuple[int, ...]]:
        rows = sorted(tables[name])
        for row in rows:
            if len(row) != width:
                sys.exit(f"{name}: expected {width} columns, found {row}")
        return rows

    letter = strided("category_Lu", "category_Ll", "category_Lt", "category_Lm", "category_Lo")
    number = strided("category_Nd", "category_Nl", "category_No")
    mark = strided("category_Mn", "category_Mc", "category_Me")
    whitespace = strided("category_Zs", "category_Zl", "category_Zp")
    control = strided("category_Cc", "category_Cf", "category_Cs", "category_Co", "category_Cn")
    lowercase = strided("category_Ll")
    uppercase = strided("category_Lu")
    titlecase = strided("category_Lt")
    cased = runs(derived["Cased"])
    case_ignorable = runs(derived["Case_Ignorable"])

    upcase = keyed("upcase_ranges", 3)
    downcase = keyed("downcase_ranges", 3)
    alternate = keyed("alternate_ranges", 2)
    casefold = keyed("casefold_ranges", 3)
    special_upcase = keyed("special_cases_upcase", 4)
    special_downcase = keyed("special_cases_downcase", 4)
    special_titlecase = keyed("special_cases_titlecase", 4)
    special_fold = keyed("fold_cases", 4)
    ccc = keyed("canonical_combining_classes", 3)
    canonical = keyed("canonical_decompositions", 3)
    compat_data = [row[0] for row in tables["compatibility_decomposition_data"]]
    compat = keyed("compatibility_decompositions", 3)
    compositions = sorted(
        (key >> 21, key & 0x1FFFFF, result)
        for key, result in tables["canonical_compositions"]
    )

    categories = general_categories(ucd)
    for name in ("Lu", "Ll", "Lt", "Lm", "Lo", "Mn", "Mc", "Me", "Nd", "Nl", "No",
                 "Zs", "Zl", "Zp", "Cc", "Cf", "Cs", "Co"):
        ours = {point for point, category in categories.items() if category == name}
        if ours != expand(tables[f"category_{name}"]):
            sys.exit(f"UnicodeData.txt and {DATA.relative_to(REPO)} disagree on {name}: not release {ucd}?")
    general_category = labelled_runs({point: CATEGORIES.index(category) for point, category in categories.items()})
    by_script = scripts(ucd)
    script_names = sorted(set(by_script.values()))
    script = labelled_runs({point: script_names.index(name) for point, name in by_script.items()})
    simple_fold = simple_only_foldings(ucd)
    grapheme = labelled_runs(grapheme_values(ucd))
    orbits = case_orbits(simple_fold, casefold, special_fold)
    orbit_index = []
    orbit_members: list[int] = []
    for folded in sorted(orbits):
        orbit_index.append((folded, len(orbit_members), len(orbits[folded])))
        orbit_members.extend(orbits[folded])

    sections = [
        f'  # The version of the Unicode Character Database the tables below were written from.\n  VERSION = "{ucd}"',
        literal("LETTER", f"{len(letter)} rows of {{from, to, stride}}: the code points of general category L (Lu, Ll, Lt, Lm, Lo).", flat(letter)),
        literal("NUMBER", f"{len(number)} rows of {{from, to, stride}}: general category N (Nd, Nl, No).", flat(number)),
        literal("MARK", f"{len(mark)} rows of {{from, to, stride}}: general category M (Mn, Mc, Me).", flat(mark)),
        literal("WHITESPACE", f"{len(whitespace)} rows of {{from, to, stride}}: general category Z (Zs, Zl, Zp).", flat(whitespace)),
        literal("CONTROL", f"{len(control)} rows of {{from, to, stride}}: general category C (Cc, Cf, Cs, Co).", flat(control)),
        literal("LOWERCASE", f"{len(lowercase)} rows of {{from, to, stride}}: general category Ll.", flat(lowercase)),
        literal("UPPERCASE", f"{len(uppercase)} rows of {{from, to, stride}}: general category Lu.", flat(uppercase)),
        literal("TITLECASE", f"{len(titlecase)} rows of {{from, to, stride}}: general category Lt.", flat(titlecase)),
        literal("CASED", f"{len(cased)} rows of {{from, to, stride}}: the Cased property of DerivedCoreProperties (Lowercase, Uppercase and Lt).", flat(cased)),
        literal("CASE_IGNORABLE", f"{len(case_ignorable)} rows of {{from, to, stride}}: the Case_Ignorable property of DerivedCoreProperties (Mn, Me, Cf, Lm, Sk and the word-internal punctuation).", flat(case_ignorable)),
        literal("UPCASE", f"{len(upcase)} rows of {{from, to, delta}}: the simple uppercase mapping of every code point in the range is itself plus delta.", flat(upcase)),
        literal("DOWNCASE", f"{len(downcase)} rows of {{from, to, delta}}: the simple lowercase mapping is itself plus delta.", flat(downcase)),
        literal("ALTERNATE", f"{len(alternate)} rows of {{from, to}}: ranges where the even code points are uppercase and the odd ones their lowercase.", flat(alternate)),
        literal("CASEFOLD", f"{len(casefold)} rows of {{from, to, delta}}: the single-code-point case folding is itself plus delta.", flat(casefold)),
        literal("SPECIAL_UPCASE", f"{len(special_upcase)} rows of {{code point, first, second, third}}: full uppercase mappings of more than one code point (0 ends a shorter one).", flat(special_upcase)),
        literal("SPECIAL_DOWNCASE", f"{len(special_downcase)} rows of {{code point, first, second, third}}: full lowercase mappings of more than one code point.", flat(special_downcase)),
        literal("SPECIAL_TITLECASE", f"{len(special_titlecase)} rows of {{code point, first, second, third}}: full titlecase mappings that differ from the uppercase mapping.", flat(special_titlecase)),
        literal("SPECIAL_FOLD", f"{len(special_fold)} rows of {{code point, first, second, third}}: full case foldings of more than one code point.", flat(special_fold)),
        literal("COMBINING_CLASS", f"{len(ccc)} rows of {{from, to, class}}: the non-zero canonical combining classes.", flat(ccc)),
        literal("CANONICAL_DECOMPOSITION", f"{len(canonical)} rows of {{code point, first, second}}: canonical decomposition mappings, Hangul syllables excluded (0 ends a singleton).", flat(canonical)),
        literal("COMPATIBILITY_DECOMPOSITION", f"{len(compat)} rows of {{code point, offset, count}}: compatibility decomposition mappings as windows of COMPATIBILITY_DATA.", flat(compat)),
        literal("COMPATIBILITY_DATA", f"{len(compat_data)} code points: the windows COMPATIBILITY_DECOMPOSITION names.", compat_data),
        literal("COMPOSITION", f"{len(compositions)} rows of {{first, second, composed}}: canonical compositions, the exclusions already left out, sorted by first then second.", flat(compositions)),
        words("CATEGORY_COUNT", "category_name", "The general categories GENERAL_CATEGORY counts in, from 0; Cn, unassigned, is the absence of a row.", CATEGORIES),
        literal("GENERAL_CATEGORY", f"{len(general_category)} rows of {{from, to, category}}: every assigned code point's general category, by its index in category_name.", flat(general_category)),
        words("SCRIPT_COUNT", "script_name", "The scripts SCRIPT counts in, from 0, as Scripts.txt names them; Unknown is the absence of a row.", script_names),
        literal("SCRIPT", f"{len(script)} rows of {{from, to, script}}: every code point's script, by its index in script_name.", flat(script)),
        literal("SIMPLE_FOLD", f"{len(simple_fold)} rows of {{code point, folded}}: the simple foldings CaseFolding.txt marks S, of code points whose full folding SPECIAL_FOLD holds.", flat(simple_fold)),
        literal("ORBIT", f"{len(orbit_index)} rows of {{folded, offset, count}}: each simple folding's orbit, as a window of ORBIT_MEMBERS.", flat(orbit_index)),
        literal("ORBIT_MEMBERS", f"{len(orbit_members)} code points: every code point that folds to an ORBIT row's folded, itself included, sorted.", orbit_members),
        literal("GRAPHEME", f"{len(grapheme)} rows of {{from, to, value}}: a code point's Grapheme_Cluster_Break in the low four bits (1 + its place in the generator's GRAPHEME_BREAKS, 0 for Other), 16 when it is Extended_Pictographic, and its Indic_Conjunct_Break from bit 5 (1 Consonant, 2 Extend, 3 Linker).", flat(grapheme)),
    ]

    module = MODULE.read_text(encoding="utf-8")
    begin = module.index(BEGIN)
    end = module.index(END)
    generated = BEGIN + "\n" + "\n\n".join(sections) + "\n" + END
    # The module's lines end in LF on every platform; a Windows text write would end them in CRLF.
    MODULE.write_text(module[:begin] + generated + module[end + len(END):], encoding="utf-8", newline="\n")
    total = sum(len(section) for section in sections)
    print(f"wrote {len(sections) - 1} tables ({total} bytes) for Unicode {ucd} into {MODULE.relative_to(REPO)}")


if __name__ == "__main__":
    main()
