#!/usr/bin/env python3
"""Compare source and artifact builds of a tape-bearing module."""
import os
from pathlib import Path
import subprocess
import tempfile

RIS = Path(os.environ.get("RIS", "./bin/ris")).resolve()

with tempfile.TemporaryDirectory(prefix="ris-iyimod-tape-") as directory:
    work = Path(directory)
    (work / "app").mkdir()
    library = work / "app/record.ri"
    library.write_text('''module app/record
@[OnTape]
pub struct Record
  getter text : String
  def initialize(@text : String)
  end
end
''')
    main = work / "main.ri"
    main.write_text('''module main
import app/record
tape do
  text = String::Builder.new
  text << "artifact tape"
  record = App::Record::Record.new(text.finish)
  puts record.text
  text.clear
end
''')

    def build(option, executable):
        subprocess.run([str(RIS), "build", option, "mods", "-o", executable,
                        str(main)], cwd=work, check=True)

    build("--emit-iyimod", "source")
    source = subprocess.check_output([str(work / "source")], text=True)
    library.unlink()
    build("--use-iyimod", "artifact")
    artifact = subprocess.check_output([str(work / "artifact")], text=True)
    assert source == artifact == "artifact tape\n", (source, artifact)
    print("runs     iyimod_tape (source and artifact match)")

    # The imported constructor must also keep the input borrow live.
    main.write_text(main.read_text().replace(
        "  puts record.text\n  text.clear",
        "  text.clear\n  puts record.text"))
    refused = subprocess.run(
        [str(RIS), "build", "--use-iyimod", "mods", "-o", "bad", str(main)],
        cwd=work, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert refused.returncode != 0, refused.stdout
    assert "cannot shrink tape storage with a live view" in refused.stdout, \
        refused.stdout
    print("refused  iyimod_tape (constructor keeps the input borrow live)")
