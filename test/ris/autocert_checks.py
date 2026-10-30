#!/usr/bin/env python3
"""Create a local PKI and run the manager/cache lifecycle gate."""
from datetime import datetime, timedelta, timezone
import os
from pathlib import Path
import subprocess
import tempfile

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

with tempfile.TemporaryDirectory(prefix="ris-autocert-") as directory:
    root = Path(directory)
    binary = root / "autocert-gate"
    build = subprocess.run([os.environ.get("RIS", "./bin/ris"), "build",
                            "-o", str(binary), "test/ris/autocert.ri"],
                           text=True, capture_output=True, timeout=900)
    if build.returncode:
        print(build.stdout + build.stderr, end="")
        raise SystemExit(build.returncode)
    now = datetime.now(timezone.utc)
    entries = []
    ca_key = ec.generate_private_key(ec.SECP256R1())
    ca_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,
                                           "autocert gate CA")])
    roots = (x509.CertificateBuilder()
             .subject_name(ca_name).issuer_name(ca_name)
             .public_key(ca_key.public_key()).serial_number(100)
             .not_valid_before(now - timedelta(seconds=1))
             .not_valid_after(now + timedelta(days=1))
             .add_extension(x509.BasicConstraints(ca=True, path_length=None),
                            critical=True)
             .sign(ca_key, hashes.SHA256())
             .public_bytes(serialization.Encoding.PEM))
    for serial, life in ((1, 15), (2, 600)):
        key = ec.generate_private_key(ec.SECP256R1())
        subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,
                                               "localhost")])
        certificate = (x509.CertificateBuilder()
                       .subject_name(subject).issuer_name(ca_name)
                       .public_key(key.public_key()).serial_number(serial)
                       .not_valid_before(now - timedelta(seconds=1))
                       .not_valid_after(now + timedelta(seconds=life))
                       .add_extension(x509.SubjectAlternativeName([
                           x509.DNSName("localhost")]), critical=False)
                       .add_extension(x509.BasicConstraints(ca=False,
                                                           path_length=None),
                                      critical=True)
                       .sign(ca_key, hashes.SHA256()))
        pem = certificate.public_bytes(serialization.Encoding.PEM)
        entries.append(key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.TraditionalOpenSSL,
            serialization.NoEncryption()) + pem)
    for child in (root, *(root / name for name in
                         ("failure", "panic", "cancel"))):
        child.mkdir(exist_ok=True)
        (child / "roots.pem").write_bytes(roots)
        for name, pem in zip(("first", "second"), entries):
            (child / f"{name}.pem").write_bytes(pem)
    result = subprocess.run([str(binary), str(root)],
                            text=True, capture_output=True, timeout=120,
                            env={**os.environ, "RIS_HEAP_STATS": "1"})
    print(result.stdout, end="")
    print(result.stderr, end="")
    raise SystemExit(result.returncode)
