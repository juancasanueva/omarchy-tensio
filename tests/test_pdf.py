"""Tests for bin/tensio_pdf.py, the dependency-free PDF report writer.

Run with: /usr/bin/python3 -m unittest discover -s tests -v
"""
import datetime
import importlib.util
import math
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = os.path.join(ROOT, "bin")

PAGE_RE = re.compile(rb"/Type /Page(?!s)")
XREF_ENTRY_RE = re.compile(rb"^(\d{10}) (\d{5}) ([nf]) ?\r?\n?$")


def load_bin_module(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(BIN, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def count_pages(data):
    return len(PAGE_RE.findall(data))


def verify_xref(testcase, data):
    """Assert the cross-reference table points at every `N 0 obj`; return the object count."""
    testcase.assertTrue(data.startswith(b"%PDF-1.4\n"), data[:16])
    testcase.assertTrue(data.rstrip(b"\r\n").endswith(b"%%EOF"), data[-16:])
    tail = data[data.rindex(b"startxref"):]
    startxref = int(tail.split(b"\n")[1])
    testcase.assertTrue(data[startxref:].startswith(b"xref\n"), data[startxref:startxref + 20])
    header = data[startxref:].split(b"\n", 2)
    first, count = (int(part) for part in header[1].split())
    testcase.assertEqual(first, 0)
    pos = startxref + len(header[0]) + 1 + len(header[1]) + 1
    for number in range(count):
        entry = data[pos:pos + 20]
        testcase.assertEqual(len(entry), 20, "xref entries are exactly 20 bytes")
        match = XREF_ENTRY_RE.match(entry)
        testcase.assertIsNotNone(match, entry)
        offset = int(match.group(1))
        if number == 0:
            testcase.assertEqual(match.group(3), b"f")
            testcase.assertEqual(int(match.group(2)), 65535)
        else:
            testcase.assertEqual(match.group(3), b"n")
            expected = b"%d 0 obj" % number
            testcase.assertEqual(data[offset:offset + len(expected)], expected, "object %d offset" % number)
        pos += 20
    trailer = data[pos:startxref + len(data[startxref:])]
    testcase.assertIn(b"/Size %d" % count, trailer)
    testcase.assertIn(b"/Root 1 0 R", trailer)
    return count


def expected_pages(pdf, rows):
    if rows <= pdf.ROWS_FIRST_PAGE:
        return 1
    return 1 + math.ceil((rows - pdf.ROWS_FIRST_PAGE) / pdf.ROWS_PER_PAGE)


def make_rows(count, start=datetime.datetime(2026, 9, 1, 7, 30)):
    rows = []
    for index in range(count):
        when = start + datetime.timedelta(hours=9 * index)
        sys_ = 110 + (index * 7) % 80
        dia = 65 + (index * 5) % 40
        rows.append({
            "when": when,
            "date": when.strftime("%b %-d, %Y"),
            "time": when.strftime("%-I:%M %p"),
            "sys": sys_, "dia": dia, "pulse": 60 + index % 30,
            "feeling": ("Good", "Tired", "")[index % 3],
            "body": ("Sitting", "Standing", "Lying", "")[index % 4],
            "arm": ("Left Arm", "Right Arm", "")[index % 3],
            "color": ("#22c55e", "#f97316", "#ef4444")[index % 3],
        })
    return rows


DISTRIBUTION = [
    {"label": "Low", "color": "#3b82f6", "pct": 0},
    {"label": "Normal", "color": "#22c55e", "pct": 50},
    {"label": "Elevated", "color": "#eab308", "pct": 10},
    {"label": "Stage 1", "color": "#f97316", "pct": 25},
    {"label": "Stage 2", "color": "#ef4444", "pct": 15},
    {"label": "Severe", "color": "#be123c", "pct": 0},
]
GENERATED = datetime.datetime(2026, 10, 6, 19, 33)


class ReportStructure(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pdf = load_bin_module("tensio_pdf")

    def build(self, count, name="Ana"):
        return self.pdf.build_report(name, "#a855f7", "Last 30 days", make_rows(count), DISTRIBUTION, GENERATED)

    def test_layout_constants_are_sane(self):
        self.assertEqual((self.pdf.PAGE_WIDTH, self.pdf.PAGE_HEIGHT), (595.0, 842.0))
        self.assertGreater(self.pdf.ROWS_FIRST_PAGE, 5)
        self.assertGreater(self.pdf.ROWS_PER_PAGE, self.pdf.ROWS_FIRST_PAGE)

    def test_page_count_and_xref_for_0_5_and_60_readings(self):
        for count in (0, 5, 60):
            data = self.build(count)
            self.assertEqual(count_pages(data), expected_pages(self.pdf, count), "rows=%d" % count)
            objects = verify_xref(self, data)
            # catalog, pages, two fonts, then a page and a content stream per page (+1 for the free entry)
            self.assertEqual(objects, 1 + 4 + 2 * expected_pages(self.pdf, count))
        self.assertGreater(count_pages(self.build(60)), 1)

    def test_every_page_carries_header_and_footer(self):
        data = self.build(60)
        pages = expected_pages(self.pdf, 60)
        self.assertEqual(data.count(b"(Blood Pressure Report) Tj"), pages)
        for number in range(1, pages + 1):
            self.assertIn(b"(%d/%d) Tj" % (number, pages), data)
        self.assertEqual(data.count(b"(Ana) Tj"), pages * 2, "name in header and footer of every page")

    def test_text_content_and_period(self):
        data = self.build(5)
        self.assertIn(b"(From Sep 1, 2026 to Sep 2, 2026) Tj", data)
        self.assertIn(b"(Distribution) Tj", data)
        self.assertIn(b"(SYS mmHg) Tj", data)
        self.assertIn(b"(Position) Tj", data)
        self.assertIn(b"(Generated 2026-10-06 19:33) Tj", data)
        self.assertIn(b"(50%) Tj", data)
        empty = self.build(0)
        self.assertIn(b"(Last 30 days) Tj", empty)
        self.assertIn(b"(No readings in this range) Tj", empty)

    def test_profile_name_is_escaped_and_encoded_as_winansi(self):
        data = self.build(1, name="Ana (Mom) \\ María ≥ 中")
        self.assertIn(b"(Ana \\(Mom\\) \\\\ Mar\xeda ? ?) Tj", data)
        self.assertIn(b"/BaseFont /Helvetica-Bold", data)
        self.assertIn(b"/Encoding /WinAnsiEncoding", data)
        self.assertNotIn(b"/Filter", data, "content streams are uncompressed")

    def test_initial_uses_first_character_or_question_mark(self):
        self.assertIn(b"(A) Tj", self.build(0, name="ana"))
        self.assertIn(b"(?) Tj", self.build(0, name="   "))


class Primitives(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pdf = load_bin_module("tensio_pdf")

    def test_pdf_string_escapes_delimiters(self):
        self.assertEqual(self.pdf.pdf_string("a(b)c\\"), b"(a\\(b\\)c\\\\)")
        self.assertEqual(self.pdf.pdf_string("line\nbreak\r"), b"(line\\nbreak\\r)")
        self.assertEqual(self.pdf.pdf_string("€"), b"(\x80)")

    def test_text_width_uses_helvetica_metrics(self):
        self.assertAlmostEqual(self.pdf.text_width("Hello", 10, False), 22.78, places=2)
        self.assertAlmostEqual(self.pdf.text_width("Hello", 10, True), 24.45, places=2)
        self.assertEqual(self.pdf.text_width("", 10, False), 0)

    def test_colours(self):
        self.assertEqual(self.pdf.hex_to_rgb("#ff0000"), (1.0, 0.0, 0.0))
        tinted = self.pdf.blend_with_white("#000000", 0.15)
        self.assertEqual(tuple(round(c, 2) for c in tinted), (0.85, 0.85, 0.85))

    def test_doc_operators(self):
        doc = self.pdf.PdfDoc()
        doc.page()
        doc.set_color("#3b82f6")
        doc.rect(10, 10, 20, 30, fill="#ffffff")
        doc.line(0, 0, 10, 10, width=1.5, color="#000000")
        doc.circle(50, 50, 4, fill="#ef4444")
        doc.text(5, 5, "Hi", size=12, bold=True, align="right")
        data = doc.render()
        self.assertEqual(count_pages(data), 1)
        verify_xref(self, data)
        self.assertIn(b"10 10 20 30 re", data)
        self.assertIn(b"re\nf\n", data)
        self.assertIn(b"1.5 w", data)
        self.assertIn(b"0 0 m\n10 10 l\nS", data)
        self.assertEqual(data.count(b" c\n"), 4, "a circle is four Bezier curves")
        self.assertIn(b"/F2 12 Tf", data)
        self.assertIn(b"(Hi) Tj", data)
        self.assertIn(b"0.231 0.51 0.965 rg", data)

    def test_page_switching_appends_to_existing_pages(self):
        doc = self.pdf.PdfDoc()
        first = doc.page()
        doc.page()
        doc.select(first)
        doc.text(1, 1, "back on first")
        self.assertEqual(doc.page_count, 2)
        data = doc.render()
        self.assertEqual(count_pages(data), 2)
        self.assertIn(b"(back on first) Tj", data)


if __name__ == "__main__":
    unittest.main()
