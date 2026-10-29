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
  def initialize
    @text = "artifact tape"
  end
end
''')
    main = work / "main.ri"
    main.write_text('''module main
import app/record
tape do
  record = App::Record::Record.new
  puts record.text
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
