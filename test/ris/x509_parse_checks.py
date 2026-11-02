#!/usr/bin/env python3
"""Check caller-owned certificate parsing against generated key fixtures."""
from datetime import datetime, timezone
import ipaddress
import os
from pathlib import Path
import subprocess
import tempfile

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, ed25519, rsa
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

ROOT = Path(__file__).resolve().parents[2]
RIS = os.environ.get("RIS", str(ROOT / "bin/ris"))


def certificate(key):
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "tape.test")])
    builder = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
               .public_key(key.public_key()).serial_number(1)
               .not_valid_before(datetime(2020, 1, 1, tzinfo=timezone.utc))
               .not_valid_after(datetime(2030, 1, 1, tzinfo=timezone.utc))
               .add_extension(x509.SubjectAlternativeName([
                   x509.DNSName("tape.test"),
                   x509.IPAddress(ipaddress.ip_address("127.0.0.1"))]), False)
               .add_extension(x509.ExtendedKeyUsage([
                   ExtendedKeyUsageOID.SERVER_AUTH]), False)
               .add_extension(x509.NameConstraints([
                   x509.DNSName(".example.test"),
                   x509.IPAddress(ipaddress.ip_network("192.0.2.0/24"))],
                   [x509.DNSName("bad.example.test")]), True)
               .add_extension(x509.SubjectKeyIdentifier(bytes(range(20))),
                              False)
               .add_extension(x509.AuthorityKeyIdentifier(
                   bytes(range(20)), None, None), False)
               .add_extension(x509.TLSFeature([
                   x509.TLSFeatureType.status_request]), False)
               .add_extension(x509.OCSPNoCheck(), False))
    algorithm = None if isinstance(key, ed25519.Ed25519PrivateKey) else \
        hashes.SHA256()
    return builder.sign(key, algorithm).public_bytes(serialization.Encoding.DER)


def tlv(tag, body):
    size = len(body)
    if size < 128:
        length = bytes([size])
    else:
        width = (size.bit_length() + 7) // 8
        length = bytes([128 + width]) + size.to_bytes(width, "big")
    return bytes([tag]) + length + body


def children(data):
    result = []
    at = 0
    while at < len(data):
        tag, size = data[at:at + 2]
        at += 2
        if size >= 128:
            width = size - 128
            size = int.from_bytes(data[at:at + width], "big")
            at += width
        result.append((tag, data[at:at + size]))
        at += size
    return result


def change_extensions(data, change):
    outer = children(children(data)[0][1])
    tbs = children(outer[0][1])
    for at, (tag, body) in enumerate(tbs):
        if tag == 0xa3:
            extensions = children(children(body)[0][1])
            changed = change(extensions)
            tbs[at] = (tag, tlv(0x30, b"".join(tlv(*x) for x in changed)))
    outer[0] = (0x30, b"".join(tlv(*x) for x in tbs))
    return tlv(0x30, b"".join(tlv(*x) for x in outer))


def main():
    with tempfile.TemporaryDirectory(prefix="ris-x509-parse-") as work:
        work = Path(work)
        binary = work / "check"
        subprocess.run([RIS, "build", "-o", str(binary),
                        str(ROOT / "test/ris/x509_parse.ri")], check=True)
        count = 0

        def check(data, expected):
            nonlocal count
            path = work / "certificate.der"
            path.write_bytes(data)
            result = subprocess.run([str(binary), str(path)], text=True,
                                    capture_output=True, timeout=30)
            assert result.returncode == 0, result.stdout + result.stderr
            assert result.stdout.strip() == expected, result.stdout
            count += 1

        good = "PASS: certificate fields survive validation"
        for curve in (ec.SECP256R1, ec.SECP384R1, ec.SECP521R1):
            # Several random valid points, plus a nearby off-curve point.
            for _ in range(8):
                key = ec.generate_private_key(curve())
                data = certificate(key)
                check(data, good)
                point = key.public_key().public_bytes(
                    serialization.Encoding.X962,
                    serialization.PublicFormat.UncompressedPoint)
                bad = point[:-1] + bytes([point[-1] ^ 1])
                try:
                    ec.EllipticCurvePublicKey.from_encoded_point(curve(), bad)
                except ValueError:
                    pass
                else:
                    raise AssertionError("mutation remained on the curve")
                label = {256: "P256", 384: "P384", 521: "P521"}[curve.key_size]
                check(data.replace(point, bad, 1),
                      f"x509: ecdsa: a point that is not on {label}")
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        data = certificate(key)
        check(data, good)
        n = key.public_key().public_numbers().n.to_bytes(256, "big")
        even = n[:-1] + bytes([n[-1] & 254])
        check(data.replace(n, even, 1),
              "x509: rsa: an even modulus, which is no product of two odd primes")
        key = ed25519.Ed25519PrivateKey.from_private_bytes(bytes(range(32)))
        data = certificate(key)
        check(data, good)
        public = key.public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        check(data.replace(public, b"\xff" * 32, 1),
              "x509: Ed25519: the public key is not a point on the curve, "
              "or not its canonical encoding")
        check(change_extensions(data, lambda items: items + [items[0]]),
              "x509: extension 2.5.29.17 appears twice")

        def bad_san(items):
            fields = children(items[0][1])
            names = tlv(0x82, b"tape.test") + tlv(0x87, b"abc")
            fields[-1] = (4, tlv(0x30, names))
            return [(0x30, b"".join(tlv(*x) for x in fields))] + items[1:]

        check(change_extensions(data, bad_san),
              "x509: an iPAddress of 3 bytes")

        def empty_usage(items):
            result = []
            for tag, body in items:
                fields = children(body)
                if fields[0] == (6, bytes.fromhex("551d25")):
                    fields[-1] = (4, tlv(0x30, b""))
                    body = b"".join(tlv(*x) for x in fields)
                result.append((tag, body))
            return result

        check(change_extensions(data, empty_usage),
              "x509: an empty extKeyUsage")
        check(b"\x30\x00", "x509: a Certificate of 0 values, not 3")
        # Keep parsed payloads on a declared, refillable root owner.
        first = certificate(ec.generate_private_key(ec.SECP256R1()))
        second = certificate(ed25519.Ed25519PrivateKey.generate())
        pem = x509.load_der_x509_certificate(first).public_bytes(
            serialization.Encoding.PEM)
        other = x509.load_der_x509_certificate(second).public_bytes(
            serialization.Encoding.PEM)
        (work / "bundle.pem").write_bytes(
            pem + pem + b"-----BEGIN CERTIFICATE-----\nAAAA\n"
            b"-----END CERTIFICATE-----\n")
        (work / "empty.pem").write_text("no certificates\n")
        roots_dir = work / "roots"
        roots_dir.mkdir()
        (roots_dir / "one.pem").write_bytes(pem)
        (roots_dir / "two.pem").write_bytes(other)
        roots_check = work / "roots-check"
        subprocess.run([RIS, "build", "-o", str(roots_check),
                        str(ROOT / "test/ris/system_roots_owner.ri")],
                       check=True)
        result = subprocess.run([str(roots_check), str(work)], text=True,
                                capture_output=True, timeout=60,
                                env=dict(os.environ, RIS_HEAP_STATS="1"))
        assert result.returncode == 0, result.stdout + result.stderr
        assert result.stdout.strip() == (
            "PASS: caller-owned system roots, refill and errors")
        assert "ris heap: 0 allocations, 0 bytes" in result.stderr
        print(f"PASS: x509 parse, {count} key, field and refusal cases")


if __name__ == "__main__":
    main()
