import hashlib
import tempfile
import unittest
from pathlib import Path

from scripts.file_hash import file_hash
from scripts.line_count import line_count


class UtilityScriptTests(unittest.TestCase):
    def test_file_hash_reads_large_files_in_chunks(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "payload"
            path.write_bytes(b"abc" * 500_000)

            self.assertEqual(file_hash(path), hashlib.sha256(path.read_bytes()).hexdigest())

    def test_file_hash_supports_a_named_algorithm(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "payload"
            path.write_text("hello", encoding="utf-8")

            self.assertEqual(file_hash(path, "md5"), hashlib.md5(b"hello").hexdigest())

    def test_line_count_preserves_empty_and_unterminated_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "lines"
            path.write_bytes(b"first\nsecond\nlast")

            self.assertEqual(line_count(path), 3)


if __name__ == "__main__":
    unittest.main()
