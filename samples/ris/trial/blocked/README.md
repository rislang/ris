# Blocked trial cases

Each file is the smallest program that shows one obstacle met while writing
the trial programs. None is run by `../run.sh`; each should be fixed in the
compiler or std, then its workaround removed from the trial program.

* `csv_reader_next.ri`, `json_parse.ri`, `json_from_json.ri`: refused in std.
* `option_parser_string.ri`: refused in the program.
* `dir_children_garbage.ri`, `hash_key_freed.ri`: compile, print garbage.
* `http_get_empty_body.ri`: compiles, the body is empty.
