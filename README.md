# utilities

Small, dependency-free Python utility scripts.

## Scripts

### File hashes

Print a SHA-256 digest (or another available `hashlib` algorithm):

```sh
python scripts/file_hash.py path/to/file
python scripts/file_hash.py --algorithm sha512 path/to/file
```

Files are read in chunks, so the hash utility does not load the whole file into
memory.

### Line counts

Count lines in one or more UTF-8 text files:

```sh
python scripts/line_count.py README.md scripts/file_hash.py
```

Run the tests with:

```sh
python -m unittest discover
```
