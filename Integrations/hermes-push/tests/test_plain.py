"""What a notification says about a reply with an inline widget."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from plain import plain  # noqa: E402  (by path: the plugin's folder name isn't a package name)


class WidgetTests(unittest.TestCase):
    def test_a_widget_line_is_left_out(self):
        reply = 'Here is the chart.\n::preview{file="chart.html" height="300"}\nTap a bar.'
        self.assertEqual(plain(reply), "Here is the chart. Tap a bar.")

    def test_a_reply_that_is_only_a_widget_says_so(self):
        self.assertEqual(plain('::preview{file="/tmp/chart.html"}'), "Sent a widget")

    def test_a_widget_line_in_code_stays(self):
        reply = '```\n::preview{file="chart.html"}\n```'
        self.assertEqual(plain(reply), '::preview{file="chart.html"}')


if __name__ == "__main__":
    unittest.main()
