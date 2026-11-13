# ris standard library specification

What each module under src/std/ promises a caller. The language's own
rules are in the root [SPEC.md](../../SPEC.md), cited here as SPEC and a
number; this file never restates them. A clause is cited by its module
and number (std json.3). Numbers never change: a new rule goes last in
its module; a removed one leaves its number unused. Modules are in
alphabetical order.

A clause ends with the test that exercises it. A clause with
`<!-- todo: Needs proof -->` has no test yet; any other todo marker
names where the code does not keep the clause today.

## acme

AcmeClient obtains certificates through ACME and supplies challenge and JWS
helpers.

* acme.1 The client reads an RFC 8555 directory and requires HTTPS with a host
  for every requested endpoint and returned resource URL before sending a
  request. (test/cli/std_acme_exercise.iyi)
* acme.2 Account registration supports contacts, terms acceptance and finding
  an existing account. External account binding is refused when required;
  roll_key uses nested JWS to move the account to a new signing key.
  (test/cli/std_acme_exercise.iyi)
* acme.3 Requests use RFC 7515 flattened JWS, RFC 8555 nonces and POST-as-GET.
  A nonce is consumed once; badNonce retries are bounded by MAX_BAD_NONCE (10)
  and counted. (test/cli/std_acme_exercise.iyi)
* acme.4 Signing supports ES256, ES384, RS256 and EdDSA. JWK thumbprints
  follow RFC 7638 canonical member order and SHA-256; base64url text omits
  padding and ECDSA JWS signatures use fixed-width R followed by S.
  (test/cli/std_acme_exercise.iyi)
* acme.5 Orders name DNS identifiers; authorization and challenge reads return
  typed status and error data. respond sends an empty JSON object after the
  caller has installed the challenge answer. (test/cli/std_acme_exercise.iyi)
* acme.6 Polling honors Retry-After seconds or HTTP dates, otherwise poll_ms.
  max_polls and wait_ms bound waiting; a requested delay beyond the remaining
  time fails immediately. (test/cli/std_acme_exercise.iyi)
* acme.7 HTTP exchanges use timeout_ms and cap response bodies at MAX_BODY
  (1048576 bytes). Protocol problem documents become AcmeError values with
  type, detail, HTTP status and one level of identifier subproblems; transport
  failures have no problem type. (test/cli/std_acme_exercise.iyi)
* acme.8 Finalization signs a PKCS #10 request with the certificate key for
  the order's names and polls until valid. certificate returns the PEM chain
  leaf first only after parsing every certificate.
  (test/cli/std_acme_exercise.iyi)
* acme.9 Key authorization is token.thumbprint. dns_txt is base64url SHA-256
  of it; dns_name removes a wildcard prefix and adds _acme-challenge.
  Publishing DNS records remains the caller's responsibility.
  (test/cli/std_acme_exercise.iyi)
* acme.10 AcmeHttp01 answers challenge paths for GET and HEAD, returns 404 for
  unknown tokens and 405 for other methods, and returns false for paths
  outside its prefix. (test/cli/std_acme_exercise.iyi)
* acme.11 RFC 8737 challenge certificates have one DNS name and a critical
  acmeIdentifier containing the authorization hash, valid from one day before
  now to seven days after. Names over 64 characters are refused by the
  certificate writer. (test/cli/std_acme_exercise.iyi)
* acme.12 Sessions and responders retain borrowed tape values under SPEC 3.2;
  returned text follows SPEC 1.5. An injected HTTPClient remains task-owned
  and must be closed by the caller.
  <!-- todo: Needs proof -->
* acme.13 This module does not schedule renewal, implement RFC 9773 renewal
  information, revoke certificates or deactivate accounts. DNS challenges
  supply values, not a DNS service.
  <!-- todo: Needs proof -->

## aead

This module provides authenticated encryption and its AES, ChaCha20 and
Poly1305 primitives.

* aead.1 AES follows FIPS 197 with 16, 24 or 32-byte keys and exactly 16-byte
  blocks; other sizes panic. Encryption and decryption return one block.
  (test/cli/std_aead_exercise.iyi)
* aead.2 AesGcm follows NIST SP 800-38D with 12-byte nonces and 16-byte tags
  only. ChaCha20Poly1305 follows RFC 8439 with 32-byte keys and 12-byte
  nonces; wrong sizes panic. (test/cli/std_aead_exercise.iyi)
* aead.3 seal appends a 16-byte authentication tag to ciphertext. Additional
  data is authenticated without encryption and defaults to empty; open returns
  plaintext or AeadError for a short input or bad tag.
  (test/cli/std_aead_exercise.iyi)
* aead.4 Opening checks all tag bytes before decrypting. Authentication
  failure leaves an in-place buffer encrypted and returns no plaintext.
  (test/cli/std_aead_exercise.iyi)
* aead.5 seal_at overwrites the requested plaintext range and writes the
  following tag; the caller supplies room for that tag. open_at overwrites
  authenticated ciphertext with plaintext and returns its length, leaving the
  tag bytes outside that length.
  <!-- todo: Needs proof -->
* aead.6 ChaCha20 streams XOR over successive calls from its selected 32-bit
  block counter. Negative counts and requesting a block after 2^32 - 1 panic;
  counter wrap is not allowed. (test/cli/std_aead_exercise.iyi)
* aead.7 Poly1305 accepts a 32-byte one-time key, accumulates updates and
  emits a 16-byte tag once; update or final after final panics.
  (test/cli/std_aead_exercise.iyi)
* aead.8 rekey replaces an authenticated cipher's stored key schedule. The
  caller supplies keys and nonces and must prevent nonce reuse; no entropy is
  drawn and secret storage is not wiped.
  <!-- todo: Needs proof -->
* aead.9 Inputs are borrowed Strings, byte arrays or byte views. Ordinary
  outputs are copied binary Strings following SPEC 1.5; in-place forms write
  caller storage. Cipher arithmetic avoids secret-indexed tables and tag
  comparison does not exit on the first differing byte.
  <!-- todo: Needs proof -->

## annotations

Compiler annotation names are available through selective imports.

* annotations.1 Deprecated, Flags, Link, Experimental and TargetFeature are
  aliases of the compiler-created root annotations; importing them does not
  create new annotation types. (test/cli/std_annotations_exercise.iyi)
* annotations.2 Flags on an enum retains compiler numbering, including None
  and All. (test/cli/std_annotations_exercise.iyi)
* annotations.3 Deprecation warnings, linking and target feature handling
  remain the compiler annotations' rules; this module adds no independent
  interpretation.
  <!-- todo: Needs proof -->

## asn1

This module reads ASN.1 DER values for certificates, keys and signatures.

* asn1.1 Der.parse reads exactly one value and rejects trailing bytes with
  Asn1Error carrying the input offset. Parsing validates framing; typed
  readers validate primitive contents. (test/cli/std_asn1_exercise.iyi)
* asn1.2 ITU-T X.690 DER headers require definite minimal lengths and minimal
  tags within supported integer bounds. Truncation and lengths exceeding their
  enclosing range return errors. (test/cli/std_asn1_exercise.iyi)
* asn1.3 Values expose class, tag, constructed flag, offsets and lengths.
  children reads one constructed level; sequence and set require the named
  type and explicit requires exactly one value in the requested constructed
  context tag. (test/cli/std_asn1_exercise.iyi)
* asn1.4 INTEGER and ENUMERATED readers require their distinct primitive tags
  and minimal nonempty two's-complement content. integer and enumerated must
  fit Int64; unsigned_integer rejects negative values and removes sign
  padding. (test/cli/std_asn1_exercise.iyi)
* asn1.5 BOOLEAN requires one byte, 00 or FF; NULL requires no content. BIT
  STRING requires zero unused bits outside its reported bit count; bit_string
  additionally requires whole bytes. (test/cli/std_asn1_exercise.iyi)
* asn1.6 OBJECT IDENTIFIER returns dotted decimal arcs, rejecting empty,
  unterminated or nonminimal subidentifiers and values beyond Int64.
  (test/cli/std_asn1_exercise.iyi)
* asn1.7 String readers validate UTF8String under RFC 3629 and the alphabets
  of PrintableString, IA5String, NumericString and VisibleString. BMPString
  and UniversalString convert big-endian Unicode to UTF-8; TeletexString uses
  ISO-8859-1. (test/cli/std_asn1_exercise.iyi)
* asn1.8 UTCTime is YYMMDDHHMMSSZ with 1950 through 2049 year interpretation.
  GeneralizedTime is YYYYMMDDHHMMSSZ with an optional decimal fraction of at
  most nine digits, no trailing zero. Invalid dates and other zones are
  refused. (test/cli/std_asn1_exercise.iyi)
* asn1.9 walk visits the root first and children in encoded order, reporting
  depth from zero and refusing depth above 64. It checks nested framing
  without decoding primitive content. (test/cli/std_asn1_exercise.iyi)
* asn1.10 SET OF ordering is not checked and no DER writer is supplied; this
  is a typed reader rather than validation of an arbitrary schema.
  (test/cli/std_asn1_exercise.iyi)
* asn1.11 DerValue and content_view borrow original bytes. content, raw and
  typed byte readers copy; child arrays still contain views. New arrays and
  decoded text follow SPEC 1.5; borrowed views follow SPEC 3.2.
  <!-- todo: Needs proof -->

## atomic

This module adds weaker memory orderings, bit operations and fences to Atomic.

* atomic.1 The admitted words are Int32, Int64, UInt8 and UInt64; other types
  are refused by the prelude. (test/cli/std_atomic_exercise.iyi)
* atomic.2 get_relaxed and set_relaxed are atomic without synchronization;
  get_acquire and set_release use acquire loads and release stores.
  (test/cli/std_atomic_exercise.iyi)
* atomic.3 add, sub and swap with relaxed, acquire, release or acq_rel
  suffixes use that ordering and return the previous word.
  (test/cli/std_atomic_exercise.iyi)
* atomic.4 compare_and_set with an ordering suffix returns the previous word
  and whether expected was exchanged for desired. Failure is acquire for
  acquire and acq_rel success, relaxed otherwise.
  (test/cli/std_atomic_exercise.iyi)
* atomic.5 and, nand, bitwise_or and xor atomically replace the word with the
  named bit operation and return its previous value, sequentially
  consistently. (test/cli/std_atomic_exercise.iyi)
* atomic.6 max and min return the old word and store the selected extremum,
  using signed comparison for signed words and unsigned comparison otherwise.
  (test/cli/std_atomic_exercise.iyi)
* atomic.7 fence, fence_acquire, fence_release and fence_acq_rel emit the
  corresponding process-wide LLVM fence. No relaxed fence is supplied.
  (test/cli/std_atomic_exercise.sh)

## autocert

Autocert manages on-demand certificate issuance and renewal for task-local
HTTP and TLS views.

* autocert.1 AutocertConfig supplies the directory, cache, allowed hosts,
  trust, terms acceptance and timing. Views normalize configured hosts and
  refuse absent or unauthorized SNI before ordinary certificate ordering.
  (test/cli/std_autocert_exercise.iyi)
* autocert.2 Autocert.run owns the process-wide order service until stop or
  cancellation. A second manager is refused even for a different cache; group
  exit joins its flights. (test/cli/std_autocert_exercise.iyi)
* autocert.3 Only one flight per name orders at once. Views post names and
  poll the shared directory cache for results; they do not run inline ACME
  orders, including when no manager is running.
  (test/cli/std_autocert_exercise.iyi)
* autocert.4 Each waiter has an independent deadline bounded by wait_ms and
  any remaining handshake time. A timed-out waiter does not cancel issuance;
  later waiters can use its completed cache entry.
  (test/cli/std_autocert_exercise.iyi)
* autocert.5 Failed orders are remembered until their recorded expiry.
  Repeated failures use retry_ms doubled up to an hour; failures are returned
  without another order until retry is due.
  (test/cli/std_autocert_exercise.iyi)
* autocert.6 Cached and issued chains must be current, match the requested
  host and verify to roots_pem, or system roots when empty, before use.
  Changed cached PEM is reloaded for later handshakes.
  (test/cli/std_autocert_exercise.iyi)
* autocert.7 Each issued certificate has one name and a fresh P-256 key.
  Renewal begins renew_before_ms before expiry, or at two thirds of a shorter
  lifetime, and publishes replacement PEM.
  (test/cli/std_autocert_exercise.iyi)
* autocert.8 Challenges are tried in configured order, default tls-alpn-01
  then http-01. TLS challenge identity is shown only when the client offers
  acme-tls/1 alone; HTTP challenge handling reads the shared cache.
  (test/cli/std_autocert_exercise.iyi)
* autocert.9 AutocertDirCache returns nil for missing keys and AutocertError
  for invalid keys or failed operations. Keys cannot be empty, dot, dot-dot or
  contain slash or backslash. (test/cli/std_autocert_exercise.iyi)
* autocert.10 Directory cache writes create a missing directory with mode
  0700, create private files with mode 0600 and rename complete entries into
  place. Readers see complete old or new data.
  (test/cli/std_autocert_exercise.iyi)
* autocert.11 Copy configuration to each worker under SPEC 5.1. Views, TLS
  configurations and mutable ACME sessions remain on their owning task's tape;
  each flight owns its session and challenge cleanup.
  <!-- todo: Needs proof -->
* autocert.12 Renewal uses certificate dates, not RFC 9773. DNS-01, wildcard
  issuance, multi-name certificates, external account binding, revocation and
  renewal jitter are not implemented.
  <!-- todo: Needs proof -->

## base32

Base32 and Base32Hex encode and decode binary text using RFC 4648.

* base32.1 Encoding follows RFC 4648 sections 6 and 7 respectively, writes
  uppercase without line breaks and pads to eight characters unless padding is
  false. (test/cli/std_base32_exercise.iyi)
* base32.2 Decoding accepts either letter case and omitted padding. Present
  padding must exactly close the last group; whitespace, foreign bytes and
  data after padding return Base32Error. (test/cli/std_base32_exercise.iyi)
* base32.3 Decoding refuses final groups of 1, 3 or 6 data characters and
  nonzero unused bits, so distinct encodings cannot hide discarded bits.
  (test/cli/std_base32_exercise.iyi)
* base32.4 Inputs and decoded results are Strings of bytes. Results follow
  SPEC 1.5; writer overloads append to the supplied builder and decoding
  errors append nothing. (src/std/base32.iyi)
  <!-- todo: Header still describes Array(UInt8) input and output. -->

## benchmark

Benchmark measures elapsed wall time and reports repeated block throughput.

* benchmark.1 measure runs the block once and returns its label and elapsed
  monotonic seconds; realtime returns the elapsed Span.
  (test/cli/std_benchmark_exercise.iyi)
* benchmark.2 bm registers labelled blocks, runs them in registration order
  and prints a real-time column without invented CPU time columns.
  (test/cli/std_benchmark_exercise.iyi)
* benchmark.3 ips warms up each block, chooses batches of at least one
  iteration, then measures throughput samples. Numeric durations denote
  seconds; spans are also accepted. (test/cli/std_benchmark_exercise.iyi)
* benchmark.4 Entry statistics use the arithmetic mean and population
  variance, its square root as standard deviation and percentage relative
  deviation; empty samples give zero. (test/cli/std_benchmark_exercise.iyi)
* benchmark.5 Reports format rates with k, M or G suffixes and time per
  iteration, and compare each measured mean with the fastest mean. Allocation
  bytes and CPU usage are not reported. (test/cli/std_benchmark_exercise.iyi)
* benchmark.6 The interactive argument is accepted but does not change
  execution or reporting. Registered blocks and labels remain borrowed by
  their job; their lifetimes obey SPEC 3.2.
  <!-- todo: Needs proof -->

## big

BigInt, BigDecimal, BigRational and BigFloat provide pure numeric computation
at arbitrary precision.

* big.1 BigInt parses signed numbers in bases 2 through 36 and prints
  lowercase digits. Invalid bases, malformed digits and out-of-range checked
  integer conversions panic. (test/cli/std_big_exercise.iyi)
* big.2 BigInt addition, subtraction and multiplication are exact; division
  truncates toward zero and remainder has the dividend's sign. Division or
  remainder by zero panics. (test/cli/std_big_exercise.iyi)
* big.3 Integer powers require a nonnegative exponent. gcd and lcm compute
  common divisors and multiples; comparisons and hashing use numeric value.
  (test/cli/std_big_exercise.iyi)
* big.4 BigInt bit operations use infinite two's-complement sign extension.
  Shifts and byte conversions preserve the represented integer; from_bytes
  reads unsigned big-endian bytes and to_bytes returns nil if the value cannot
  fit. (test/cli/std_big_exercise.iyi)
* big.5 pow_mod requires a positive modulus and nonnegative exponent and
  returns the nonnegative residue. pow_mod_secret additionally requires an odd
  modulus. (test/cli/std_big_exercise.iyi)
* big.6 inverse_mod_secret requires a positive odd modulus, returns the
  nonnegative inverse, and returns nil if none exists; modulo one returns
  zero. (test/cli/std_big_exercise.iyi)
* big.7 Secret modular exponentiation uses fixed windows and reads every table
  entry. Secret inversion rounds depend on modulus width; initial reduction
  and result size are not hidden.
  <!-- todo: Needs proof -->
* big.8 BigDecimal represents an integer times a decimal power. Addition,
  subtraction and multiplication are exact; division rounds half away from
  zero to the requested fractional precision, default 20.
  (test/cli/std_big_exercise.iyi)
* big.9 BigDecimal equality and hashing ignore redundant decimal zeros; zero
  prints as 0. Conversion to an integer discards the fractional part.
  (test/cli/std_big_exercise.iyi)
* big.10 BigRational reduces every numerator and denominator to a positive
  denominator; zero denominators panic. Arithmetic is exact and equality and
  hashing agree on reduced values. (test/cli/std_big_exercise.iyi)
* big.11 BigFloat defaults to 128 bits, rounds results to nearest with ties to
  even, and uses the larger operand precision for two BigFloat operands.
  Integer operands keep the float's precision. (test/cli/std_big_exercise.iyi)
* big.12 BigFloat refuses precision below one, nonfinite input, division by
  zero and square root of a negative number. parse? returns nil for malformed
  text. (test/cli/std_big_exercise.iyi)
* big.13 BigFloat text uses the fewest decimal digits that round back at its
  precision, positional from 1e-4 to below 1e15 and exponent notation outside
  that range. (test/cli/std_big_exercise.iyi)
* big.14 Numeric structs containing limb arrays borrow or own tape data, not a
  foreign GMP allocation. Returned limb storage follows SPEC 1.5; retaining a
  borrowed numeric value follows SPEC 3.2.
  <!-- todo: Needs proof -->
* big.15 BigFloat to_big_i and trunc discard the fractional part toward zero,
  floor and ceil choose the adjacent integer in their named direction, and
  round chooses the nearest integer with ties to even. with_precision rounds
  to the requested bit precision. (test/cli/std_big_exercise.iyi)

## bit_array

BitArray stores a fixed count of Boolean values in packed words.

* bit_array.1 Construction accepts sizes from zero through 2147483647 and
  initializes all bits to false unless a value or index block is supplied;
  other sizes panic. (test/cli/std_bit_array_exercise.iyi)
* bit_array.2 Checked access and assignment accept negative indices from the
  end. Out-of-range access panics, while []? returns nil; first and last have
  the same empty versus nil distinction. (test/cli/std_bit_array_exercise.iyi)
* bit_array.3 toggle changes one bit, invert changes every logical bit, and
  fill changes all bits or a range. Range fill clips to the end, ignores
  nonpositive counts and otherwise rejects a start outside 0..size.
  (test/cli/std_bit_array_exercise.iyi)
* bit_array.4 all?, any?, none?, one?, includes? and count inspect only
  logical bits. For an empty array all? and none? are true.
  (test/cli/std_bit_array_exercise.iyi)
* bit_array.5 index and rindex search from the supplied offset, support
  negative offsets and return nil outside the array or when no matching bit is
  found. Iteration visits logical indices in order.
  (test/cli/std_bit_array_exercise.iyi)
* bit_array.6 reverse_in_place reverses the bits; rotate_in_place moves a
  positive count left modulo size, with negative counts moving right. Arrays
  of at most one bit are unchanged. (test/cli/std_bit_array_exercise.iyi)
* bit_array.7 dup and clone copy the packed words independently. to_slice
  copies bytes in little-endian word order with bit zero in the low bit and
  unused high bits zero. (test/cli/std_bit_array_exercise.iyi)
* bit_array.8 Equality compares size and bits; hashing agrees with equality.
  to_s and inspect write BitArray[ followed by 0 or 1 per bit and ].
  (test/cli/std_bit_array_exercise.iyi)
* bit_array.9 Packed words and exported byte copies live on tape; copies and
  formatted results follow SPEC 1.5. Assignment of the struct aliases its
  array under SPEC 1.4.
  <!-- todo: Needs proof -->

## bool

This module extends the prelude Bool with eager operations and conversions.

* bool.1 The | and & operators evaluate both operands and return Boolean
  disjunction and conjunction; ^ is true exactly when the operands differ.
  (test/cli/std_bool_exercise.iyi)
* bool.2 to_unsafe returns Int32 1 for true and 0 for false; clone returns the
  same Boolean value. (test/cli/std_bool_exercise.iyi)
* bool.3 to_s(io) writes the same text as the prelude to_s; hash is 1231 for
  true and 1237 for false. (test/cli/std_bool_exercise.iyi)

## box

Box holds a typed value for passing opaque context through a foreign call.

* box.1 A Box(T) retains its object and unbox of that box's pointer returns it
  as T. (test/cli/std_box_exercise.iyi)
* box.2 Unboxing a null pointer returns nil when T admits nil, and otherwise
  panics with Unboxing null pointer. (test/cli/std_box_exercise.iyi)
* box.3 to_unsafe returns the box's address without copying its object. The
  pointer is valid only while the tape-owned box is alive; the caller must
  supply a live pointer to the matching Box(T).
  <!-- todo: Needs proof -->

## bzip2

Bzip2 compresses whole Strings and decodes whole or streamed bzip2 data.

* bzip2.1 Compression follows the bzip2 file format as libbzip2 1.0.8
  implements it, with a BZh header, level 1 through 9 and block and combined
  CRCs. Other levels panic; byte-for-byte equality with libbzip2 is not
  promised. (test/cli/std_bzip2_exercise.iyi)
* bzip2.2 Decompression checks headers, coding tables, selectors, block
  bounds, origin pointers and both CRCs. Corruption or premature end returns
  Bzip2Error; randomized blocks are refused. (test/cli/std_bzip2_exercise.iyi)
* bzip2.3 Concatenated streams decode consecutively. Bytes after the final
  stream that do not start another valid stream header are ignored by
  decompress and exposed by the reader's leftover.
  (test/cli/std_bzip2_exercise.iyi)
* bzip2.4 Bzip2Reader borrows an optional source and an initial compressed
  String, refilling only when needed. read returns at most 65536 bytes and an
  empty String at verified end; max below one panics.
  (test/cli/std_bzip2_exercise.iyi)
* bzip2.5 A reader error is sticky. Earlier reads may have exposed bytes
  before the block CRC was known; the read discovering a bad CRC returns the
  error instead of its bytes. (test/cli/std_bzip2_exercise.iyi)
* bzip2.6 The decoder retains one block's inverse-transform storage and reuses
  its input buffer. Returned Strings follow SPEC 1.5; the caller owns and
  closes the source. There is no streaming compressor.
  <!-- todo: Needs proof -->

## capsule

This module encodes HTTP datagrams and reliable-stream capsules and checks
their negotiation fields.

* capsule.1 VarInt follows RFC 9000 section 16: unsigned values through 2^62 -
  1 use 1, 2, 4 or 8 bytes with a two-bit length prefix. Default encoding is
  shortest; explicit lengths must be valid and fit the value.
  (test/cli/std_capsule_exercise.iyi)
* capsule.2 VarInt decoding returns the value and consumed byte count. Default
  decoding permits longer encodings; strict decoding refuses them. Question
  forms return nil on invalid input, other forms panic.
  (test/cli/std_capsule_exercise.iyi)
* capsule.3 HttpDatagram follows RFC 9297 section 2: a quarter stream ID
  precedes the payload and is at most 2^60 - 1. from_stream_id accepts only
  client-initiated bidirectional IDs divisible by four.
  (test/cli/std_capsule_exercise.iyi)
* capsule.4 Capsule encodes RFC 9297 section 3's type, length and value
  framing. Truncated headers or values are refused, including lengths outside
  the available bytes. (test/cli/std_capsule_exercise.iyi)
* capsule.5 read_all preserves unknown capsule types; read_known skips them.
  read_with_skip_count appends recognized capsules to its supplied array and
  returns the number skipped. (test/cli/std_capsule_exercise.iyi)
* capsule.6 ExtendedConnect exposes setting 0x08 from RFC 8441 and RFC 9220.
  Its request check requires CONNECT and nonempty protocol, scheme, authority
  and path; its response check accepts status 200 through 299. It does not
  perform HTTP transport negotiation. (test/cli/std_capsule_exercise.iyi)
* capsule.7 CapsuleProtocol matches its header name without case and accepts a
  true Boolean Item Structured Field under RFC 8941, parsing and ignoring
  valid parameters as RFC 9297 requires. Malformed fields do not enable
  capsules. (test/cli/std_capsule_exercise.iyi)
* capsule.8 Decoded payloads and capsule values are slices viewing the input;
  encoded bytes and result arrays follow SPEC 1.5. A caller retaining decoded
  views must retain the source under SPEC 3.2.
  <!-- todo: Needs proof -->

## colorize

Colorize wraps values in terminal colour and style escapes.

* colorize.1 Colour wrappers support sixteen named ANSI colours, UInt8 palette
  colours and three UInt8 RGB components for foreground and background.
  Unknown symbolic colour names panic. (test/cli/std_colorize_exercise.iyi)
* colorize.2 Style selection has one slot: bold, dim, underline, blink,
  reverse or hidden; the last style wins and bright means bold.
  (test/cli/std_colorize_exercise.iyi)
* colorize.3 Enabled formatting writes ANSI SGR prefixes and a reset after the
  value. Disabled formatting writes the value alone; toggle can disable an
  individual wrapper. (test/cli/std_colorize_exercise.iyi)
* colorize.4 The default enabled state is cached from the environment and
  requires both stdout and stderr to be terminals, no nonempty NO_COLOR and
  TERM other than dumb. Explicit enabled assignment overrides that choice.
  (test/cli/std_colorize_exercise.sh)
* colorize.5 reset writes the reset escape only when globally enabled. with
  returns an empty wrapped String, and Object#colorize wraps arbitrary
  printable values. (test/cli/std_colorize_exercise.iyi)
* colorize.6 A wrapper retains its target without copying it; fluent choices
  return new wrapper values. Formatted Strings follow SPEC 1.5 and stream
  overloads write to the supplied output.
  <!-- todo: Needs proof -->

## complex

Complex computes with Float64 real and imaginary components.

* complex.1 Construction converts numeric components to Float64. A real number
  equals a Complex exactly when its value equals the real component and the
  imaginary component is zero; hashes agree for that case.
  (test/cli/std_complex_exercise.iyi)
* complex.2 Addition, subtraction, multiplication and division support Complex
  and real operands on either side. Division uses scaled quotients; zero
  divisors follow floating-point infinity and NaN behaviour.
  (test/cli/std_complex_exercise.iyi)
* complex.3 to_f64, to_f32 and integer conversions refuse nonzero imaginary
  components, then use the real component's conversion. clone and to_c return
  the same value. (test/cli/std_complex_exercise.iyi)
* complex.4 abs uses hypot, abs2 is the sum of component squares, phase uses
  atan2, and polar returns magnitude and phase. conj negates the imaginary
  component including its signed zero. (test/cli/std_complex_exercise.iyi)
* complex.5 sign returns zero unchanged, unit direction for other finite
  values and normalized directions for infinite components; a NaN component
  yields two NaNs. inv computes the reciprocal with scaling for extreme
  magnitudes. (test/cli/std_complex_exercise.iyi)
* complex.6 exp, log and sqrt use the principal branch. Signed imaginary zero
  selects the side of the negative-real branch cut; a real exponential keeps
  its imaginary zero even on overflow. (test/cli/std_complex_exercise.iyi)
* complex.7 round rounds both parts. Number#i supplies an imaginary value and
  cis supplies cosine plus sine times i. Text is real, a spaced sign and
  imaginary magnitude followed by i; inspect adds parentheses.
  (test/cli/std_complex_exercise.iyi)
* complex.8 Complex holds only two scalar values. Generated Strings follow
  SPEC 1.5; output overloads write to the supplied stream.
  <!-- todo: Needs proof -->

## compress

This module compresses and decompresses raw DEFLATE, zlib and gzip byte
Strings.

* compress.1 Deflate follows RFC 1951, Zlib RFC 1950 and Gzip RFC 1952.
  Compression accepts levels 0 through 9, default 6; zero stores uncompressed
  blocks and invalid levels panic. (test/cli/std_compress_exercise.iyi)
* compress.2 Decoders validate block types, Huffman trees, lengths, distances
  and available input. Zlib checks its header and Adler-32; gzip checks
  headers, CRC-32 and uncompressed length.
  (test/cli/std_compress_exercise.iyi)
* compress.3 Whole-string decompress calls panic on invalid data. Inflater
  instead returns CompressError and repeats the same error on later reads;
  bytes decoded by the failing read are not returned.
  (test/cli/std_compress_exercise.iyi)
* compress.4 Inflater reads its optional source only as needed after its
  initial head. read returns up to max bytes, possibly fewer before EOF; max
  below one panics and empty text denotes verified end.
  (test/cli/std_compress_exercise.iyi)
* compress.5 Gzip concatenated members are decoded consecutively. leftover
  exposes bytes already read beyond the stream, and finished? requires the
  trailer checked and all output delivered.
  (test/cli/std_compress_exercise.iyi)
* compress.6 Deflater preserves its history between compress calls and ends
  each nonempty piece with sync flush. finish writes a final block and
  envelope trailer once; compression or another finish afterward panics until
  reset. (test/cli/std_compress_exercise.iyi)
* compress.7 Streaming compression accepts window_bits 8 through 15 and levels
  0 through 9. reset reuses storage for a new stream and configure changes
  level and window settings. (test/cli/std_compress_exercise.iyi)
* compress.8 Inflater.flushed decodes complete raw flush pieces while
  retaining history. A malformed piece makes failure sticky; output above
  limit returns nil and fails the stream. reset discards its history.
  (test/cli/std_compress_exercise.iyi)
* compress.9 read on a flushed inflater, inflate on an ordinary inflater and
  reset on an ordinary inflater panic. Preset zlib dictionaries are refused
  and no filtered, Huffman-only or RLE strategy is exposed.
  (test/cli/std_compress_exercise.iyi)
* compress.10 Input Strings are borrowed, streaming history and buffers are
  reused, and returned byte Strings follow SPEC 1.5. Sources are caller-owned
  and must be closed by the caller.
  <!-- todo: Needs proof -->

## cookie

Cookie reads and writes cookie fields; CookieJar stores client cookies for
matching requests.

* cookie.1 Cookie.parse follows RFC 6265 section 5.2's name-value and
  attribute parsing, ignores unknown attributes and returns nil without a
  nonempty name-value pair. Attribute names ignore case and a leading domain
  dot is removed. (test/cli/std_cookie_exercise.iyi)
* cookie.2 Expires accepts the three HTTP date forms; a valid Max-Age takes
  precedence. Nonpositive age expires immediately, absent expiry denotes a
  session cookie and expired? includes equality with the supplied instant.
  (test/cli/std_cookie_exercise.iyi)
* cookie.3 to_set_cookie requires a token name and RFC 6265 cookie-octet value
  and panics on invalid ones. It writes path, domain, lifetime and flag
  attributes, using Max-Age before Expires. (test/cli/std_cookie_exercise.iyi)
* cookie.4 parse_header appends name-value pairs to the supplied hash, removes
  surrounding quotes and keeps the first occurrence of a repeated name.
  from_response parses each Set-Cookie field separately.
  (test/cli/std_cookie_exercise.iyi)
* cookie.5 A jar replaces cookies with the same name, effective domain and
  path and removes replacements already expired. Host-only cookies return only
  to their original host; explicit domains must match and contain a dot.
  (test/cli/std_cookie_exercise.iyi)
* cookie.6 Selection requires domain, slash-boundary path and lifetime
  matching. Secure cookies are accepted and sent only for https or wss;
  matching cookies are ordered by longer path then older stored entry.
  (test/cli/std_cookie_exercise.iyi)
* cookie.7 An insecure response must not replace an existing Secure cookie.
  <!-- todo: Insecure replacement ignores stored Secure flags; Needs proof. -->
* cookie.8 header_for returns nil for no matches and otherwise joins
  name=value pairs with semicolon and space. The jar has no public-suffix list
  and can accept co.uk; it does not implement browser SameSite request policy.
  (test/cli/std_cookie_exercise.iyi)
* cookie.9 Parsed names, values and paths view input, while normalized domains
  use builder storage. Jar insertion copies retained text into its own
  builder; selection arrays borrow that text. Output text follows SPEC 1.5 and
  retained views follow SPEC 3.2.
  <!-- todo: Needs proof -->

## crypto

Crypto supplies keyed hashes, key derivation and comparison over digest
algorithms.

* crypto.1 HMAC implements RFC 2104 with the selected digest, hashing keys
  longer than its block and zero-padding shorter ones. Streaming and one-shot
  MACs return the same bytes; hexadecimal output is lowercase.
  (test/cli/std_crypto_exercise.iyi)
* crypto.2 HMAC update accumulates bytes until final. A second final, update
  after final or a destination shorter than digest_size panics; reset restores
  the keyed initial state for a new message.
  (test/cli/std_crypto_exercise.iyi)
* crypto.3 HKDF extract and expand implement RFC 5869; derive composes them.
  Empty salt is the default zero key, output may be empty, and lengths outside
  zero through 255 digest outputs panic. (test/cli/std_crypto_exercise.iyi)
* crypto.4 PBKDF2 follows RFC 8018 section 5.2 with HMAC and big-endian block
  indices. Iteration counts and output lengths below one panic.
  (test/cli/std_crypto_exercise.iyi)
* crypto.5 constant_time_compare returns false immediately for different
  lengths; for equal lengths it reads every byte and combines differences
  without stopping at their first mismatch. (test/cli/std_crypto_exercise.iyi)
* crypto.6 String and byte-view inputs are borrowed. Derived byte arrays and
  hex Strings follow SPEC 1.5; final(dst) writes caller storage. HMAC keeps
  keyed digest states and reuses them on reset.
  <!-- todo: Needs proof -->

## csv

CSV parses and writes comma-separated tables and supplies configurable
streaming readers and writers.

* csv.1 Default CSV follows RFC 4180 quoting and doubled quotes, with LF, CRLF
  and lone CR accepted as line ends. Blank lines are rows with zero fields; a
  leading UTF-8 BOM is skipped and UTF-16 BOMs are refused.
  (test/cli/std_csv_exercise.iyi)
* csv.2 CSV.parse yields one row at a time, panicking on malformed quotation.
  Fields view input or a reused row buffer and are valid only during the
  callback; retaining rows requires copy_to(owner).
  (test/cli/std_csv_exercise.iyi)
* csv.3 CSV.build quotes separator, quote and newline bytes, doubles quotes,
  distinguishes one empty field from a blank row and protects a first field
  beginning with a BOM. Its final empty row is terminated.
  (test/cli/std_csv_exercise.iyi)
* csv.4 CSVReader accepts a String or IyiIO and reuses a 64 KiB input window.
  next_row returns fields, next returns CSVRow and both return nil at EOF or
  CSVError on malformed input. (test/cli/std_csv_exercise.iyi)
* csv.5 Reader separators and quotes must be distinct ASCII characters other
  than line ends. strip removes surrounding spaces and tabs; same_size rejects
  rows differing in width from the first row or header.
  (test/cli/std_csv_exercise.iyi)
* csv.6 With headers enabled the first row supplies names, later duplicate
  names win and blank data lines are skipped. CSVRow supports numeric and
  named lookup; question forms return nil when absent, checked forms panic.
  (test/cli/std_csv_exercise.iyi)
* csv.7 CSVError records line and character column from one, counting CRLF as
  one line end. Unterminated quotes name their opening position; errors remain
  sticky on subsequent reads. (test/cli/std_csv_exercise.iyi)
* csv.8 CSVWriter writes rows to its caller's stream, with LF, CRLF or CR
  termination. It quotes whitespace at field edges as well as delimiters and
  quotes, supports quote_all, counts written rows and forwards flush.
  (test/cli/std_csv_exercise.iyi)
* csv.9 Reader fields and CSVRow share storage valid until the next read.
  Header storage is retained by the reader; builders and whole-document
  results follow SPEC 1.5. Readers and writers do not own or close the
  supplied stream.
  <!-- todo: Needs proof -->

## curve25519

This module provides X25519 key agreement and Ed25519 signatures without an
entropy source.

* curve25519.1 X25519 implements RFC 7748 with 32-byte private and public
  keys, scalar clamping and masking the peer coordinate's top bit.
  Noncanonical peer coordinates are reduced rather than rejected.
  (test/cli/std_curve25519_exercise.iyi)
* curve25519.2 public_key returns 32 bytes. shared returns 32 bytes or
  CurveError for a wrong-sized peer key or an all-zero shared secret; a
  wrong-sized private key panics. (test/cli/std_curve25519_exercise.iyi)
* curve25519.3 Ed25519 implements RFC 8032 section 5.1 from a 32-byte seed:
  public_key returns 32 bytes and deterministic sign returns 64. Wrong seed
  sizes panic; the caller supplies secret entropy.
  (test/cli/std_curve25519_exercise.iyi)
* curve25519.4 verify returns false for malformed key or signature sizes, a
  noncanonical or off-curve public key, S at least the group order or a failed
  cofactorless verification equation. Canonical small-order public keys are
  not independently refused. (test/cli/std_curve25519_exercise.iyi)
* curve25519.5 Ed25519PublicKey.from_bytes validates and retains a copied
  public key or returns CurveError; its verify checks signatures using that
  prepared key. (test/cli/std_curve25519_exercise.iyi)
* curve25519.6 Secret scalar operations use fixed work and masked selection
  rather than secret-indexed table reads. Verification operates on public data
  and may use variable-time arithmetic.
  <!-- todo: Needs proof -->
* curve25519.7 Inputs are borrowed Strings or byte views; output keys,
  signatures and shared secrets are binary Strings under SPEC 1.5. Prepared
  key storage belongs to its tape owner, and no secret wiping is promised.
  <!-- todo: Needs proof -->

## debug

This is an internal module for resolving runtime panic frames from native
executable debug information.

* debug.1 Importing the module installs frame resolution; Linux also installs
  an .eh_frame stack walker. Programs can still panic without importing it.
  (test/cli/std_debug_exercise.sh)
* debug.2 On Linux, frames are resolved from /proc/self/exe symbol and DWARF
  line sections, including relocated executable addresses. Missing debug data
  leaves address frames. (test/cli/std_debug_exercise.sh)
* debug.3 On Darwin, companion .dwarf and .dSYM data supplies source
  locations; supported DWARF line tables map addresses to file, line and
  column without an external symbolizer. (test/cli/std_debug_exercise.sh)
* debug.4 The inherited Windows implementation reads matching CodeView PDB
  data beside the executable; missing data leaves addresses. Supported ris
  targets remain those of SPEC 7.1. (test/cli/panics.sh)
* debug.5 Frame resolution writes diagnostics itself; callers do not receive
  owned debug handles or close mappings. Native parsing helpers are runtime
  implementation details, not general file-format APIs.
  <!-- todo: Needs proof -->

## deque

Deque is an indexable double-ended sequence backed by a ring buffer.

* deque.1 Construction creates an empty queue, reserves nonnegative capacity
  or fills a nonnegative size with a value or index block. Negative sizes and
  capacities panic. (test/cli/std_deque_exercise.iyi)
* deque.2 push and unshift append and prepend and return the queue; pop and
  shift remove and return the respective end. Empty removal panics while
  question forms return nil; count removal clips to size and negative counts
  panic. (test/cli/std_deque_exercise.iyi)
* deque.3 Checked indexing and assignment use logical order and accept
  negative indices from the end. Out-of-range access panics and question
  access returns nil. (test/cli/std_deque_exercise.iyi)
* deque.4 insert and delete_at preserve logical element order while moving the
  shorter side. Insertion allows the end position; deletion returns the
  removed element and invalid indices panic. (test/cli/std_deque_exercise.iyi)
* deque.5 rotate_in_place rotates positive counts left modulo size and
  negative counts right. concat appends a deque or array in order, including a
  finite copy of the original sequence on self-concatenation.
  (test/cli/std_deque_exercise.iyi)
* deque.6 clear removes every logical element and preserves capacity.
  Iteration and Indexable, IndexableMutable and Enumerable operations observe
  logical ring order. (test/cli/std_deque_exercise.iyi)
* deque.7 Equality compares element count and ordered values for compatible
  element types. to_s and inspect write Deque{ with inspected elements
  separated by comma and space and a closing brace.
  (test/cli/std_deque_exercise.iyi)
* deque.8 The queue owns tape-backed ring storage; assignments alias the
  queue. Growth may rearrange logical slots, so callers use checked indices
  rather than retaining physical slot references under SPEC 3.2.
  <!-- todo: Needs proof -->

## derives

This module supplies example derive macros and a Show trait for field-aware
rendering.

* derives.1 Name stores borrowed text and implements Show by returning that
  text between < and >; generated text follows SPEC 1.5.
  <!-- todo: Needs proof -->
* derives.2 described generates a described method with the declaration's
  name, an opening parenthesis, each field name=value followed by space in
  declaration order and a closing parenthesis. Values use to_s.
  <!-- todo: Needs proof -->
* derives.3 shown generates a shown method containing name=show followed by
  space only for fields whose visible type implements Show. Fields with no
  visible type or without that trait contribute nothing.
  <!-- todo: Needs proof -->

## digest

Digest supplies incremental hashes, extendable output and checksums without
foreign crypto libraries.

* digest.1 MD5 follows RFC 1321, SHA-1 RFC 3174 and SHA-224, SHA-256, SHA-384
  and SHA-512 FIPS 180-4. Hash bytes are in the algorithm's standard order and
  hexadecimal text is lowercase. (test/cli/std_digest_exercise.iyi)
* digest.2 SHA3-224, SHA3-256, SHA3-384 and SHA3-512 implement FIPS 202 with
  their defined digest sizes. One-shot and incremental hashing produce the
  same digest. (test/cli/std_digest_exercise.iyi)
* digest.3 Digest update consumes String or byte-view bytes and returns self.
  final emits exactly digest_size bytes, or writes the prefix of an adequately
  sized destination; too-small destinations panic.
  (test/cli/std_digest_exercise.iyi)
* digest.4 After final, update and another final panic until reset. reset
  restores the initial state; copy_from copies state only from the same
  concrete algorithm and dup has independent state.
  (test/cli/std_digest_exercise.iyi)
* digest.5 SHAKE128 and SHAKE256 follow FIPS 202's extendable output:
  successive read(n) calls continue the output stream; update after reading is
  refused until reset. (test/cli/std_digest_exercise.iyi)
* digest.6 CRC32 computes the reflected ISO 3309 CRC-32, Adler32 follows RFC
  1950 and CRC64 implements CRC-64/XZ with the reflected ECMA-182 polynomial
  and inverted initial and final state. Incremental checksum updates continue
  the same checksum as a single combined input.
  (test/cli/std_digest_exercise.iyi)
* digest.7 XXH64 supports a seed and incremental input; digest can be queried
  before more updates without consuming state and reset begins another hash.
  (test/cli/std_digest_exercise.iyi)
* digest.8 Input bytes are borrowed and digest states retain only their
  working blocks. Newly returned arrays and hex Strings follow SPEC 1.5;
  final(writer) appends to caller storage. Table storage is initialized once
  on Program.tape.
  <!-- todo: Needs proof -->

## dir

Dir opens directory streams, lists names, changes directories and expands file
patterns.

* dir.1 Opening a missing or inaccessible directory panics. A non-block stream
  must be closed explicitly; block open closes on exit. close is idempotent,
  closed? reports state and reads or rewind after closing panic.
  (test/cli/std_dir_exercise.iyi)
* dir.2 read returns the next entry name or nil at end and rewind restarts the
  stream. each continues at the current position; whole listings and
  each_child restart from the beginning; children variants omit . and .. while
  entries retain them. (test/cli/std_dir_exercise.iyi)
* dir.3 current returns the working directory. cd changes it, and block cd
  restores the previous directory on exit. tempdir consults platform
  environment defaults and removes one trailing separator while preserving a
  root. (test/cli/std_dir_exercise.iyi)
* dir.4 exists? distinguishes directories from regular files and missing
  paths. empty? checks for entries other than . and ..; mkdir creates one
  directory and mkdir_p creates missing parents.
  (test/cli/std_dir_exercise.iyi)
* dir.5 delete and rmdir remove an empty directory and panic on failure;
  delete? returns false on failure. Existing non-directory parents are refused
  by mkdir_p. (test/cli/std_dir_exercise.iyi)
* dir.6 glob expands braces and matches path segments using File.match?,
  including *, ?, character classes and escapes. ** spans zero or more
  directories and never descends through directory symlinks.
  (test/cli/std_dir_exercise.iyi)
* dir.7 Wildcards omit hidden names unless their segment starts with a dot. A
  trailing separator selects directories and is preserved; joined results
  retain the pattern's separator spelling. (test/cli/std_dir_exercise.iyi)
* dir.8 read copies each returned name. Listing arrays refer to their
  collected text; glob with a builder appends retained names into that
  builder, whereas callback names are borrowed for the callback. Returned
  storage follows SPEC 1.5 and retention follows SPEC 3.2.
  <!-- todo: Needs proof -->
* dir.9 Directory read errors must be distinguished from end of directory.
  <!-- todo: Linux read treats getdents64 errors as EOF; Needs proof. -->

## dns

This module reads and writes DNS packets and parses resolver configuration
without doing network IO.

* dns.1 DnsName accepts ASCII labels of 1 through 63 bytes with letters,
  digits, hyphen and underscore, no leading hyphen and no entirely numeric
  final label. Total written length is at most 253 bytes excluding one
  trailing dot. (test/cli/std_dns_exercise.iyi)
* dns.2 Name equality ignores ASCII case and one trailing dot. Search
  candidates use search domains and ndots, trying an absolute trailing-dot
  name alone omitting empty search suffixes and candidates exceeding the name
  bound. (test/cli/std_dns_exercise.iyi)
* dns.3 DnsTapeMessage writes RFC 1035 queries and parses headers, questions
  and records with bounded lengths. Malformed packets return DnsError;
  compression pointers must move to earlier occurrences and cannot cycle.
  (test/cli/std_dns_exercise.iyi)
* dns.4 answers? requires response status, matching ID and the original
  question's case-insensitive name, type and class. Address collection follows
  CNAME links only up to MAX_CNAMES. (test/cli/std_dns_exercise.iyi)
* dns.5 Plain queries carry no EDNS. A positive padding block requests an
  EDNS(0) OPT with RFC 7830 Padding for encrypted transports; response OPT
  data supplies extended RCODE bits, not general EDNS processing.
  (test/cli/std_dns_exercise.iyi)
* dns.6 Records expose owner, type, class, TTL and raw data, plus decoded
  targets where supported. character_strings returns the sequence of
  length-prefixed character strings or nil on truncation.
  (test/cli/std_dns_exercise.iyi)
* dns.7 SvcbRecord reads RFC 9460 SVCB and HTTPS data: uncompressed target
  names, strictly increasing unique keys, bounded parameter values and valid
  mandatory, ALPN, port and address-hint forms. Missing mandatory values and
  no-default-alpn without alpn are refused. (test/cli/std_dns_exercise.iyi)
* dns.8 Service bindings expose AliasMode, endpoint, protocol list, port, ECH
  and address hints; unknown parameter keys remain available as raw values.
  SvcbStore retains records and orders service priorities.
  (test/cli/std_dns_exercise.iyi)
* dns.9 ResolvConf reads at most three nameservers, lets the later search or
  domain directive win and clamps ndots to 0..15, timeout to 1..30 seconds and
  attempts to 1..5. Unknown directives and malformed option numbers are
  ignored. (test/cli/std_dns_exercise.iyi)
* dns.10 HostsFile returns matching addresses in file order, matching aliases
  without case or trailing-dot differences. Space, tab and carriage return
  split words and # or semicolon starts a comment.
  (test/cli/std_dns_exercise.iyi)
* dns.11 Configuration names and raw record data may view input. SvcbRecord
  copies target and parameter bytes to its retained text storage, and
  SvcbStore retains them. Results follow SPEC 1.5 and views SPEC 3.2.
  <!-- todo: Needs proof -->
* dns.12 Network retries, TCP fallback and encrypted transports belong to
  resolver modules. This module supplies no DNS cache, DNSSEC validation or
  reverse lookup service.
  <!-- todo: Needs proof -->

## ecdsa

This module checks ECDSA public keys and signatures on the NIST prime curves.

* ecdsa.1 EcdsaCurve describes P-256, P-384 and P-521 and maps their RFC 5480
  named-curve OIDs. EcdsaHash supports SHA-256, SHA-384 and SHA-512.
  (test/cli/std_ecdsa_exercise.iyi)
* ecdsa.2 from_point accepts only fixed-width uncompressed SEC 1 points
  beginning 04. Wrong lengths, compressed encodings, coordinates outside the
  field and points off the curve return EcdsaError.
  (test/cli/std_ecdsa_exercise.iyi)
* ecdsa.3 from_spki requires strict DER SubjectPublicKeyInfo with
  id-ecPublicKey and a supported named curve. Explicit parameters and invalid
  public point bits return EcdsaError. (test/cli/std_ecdsa_exercise.iyi)
* ecdsa.4 verify follows SEC 1 section 4.1.4 with the requested hash,
  truncating longer hashes to order bit length. Signature DER must be exactly
  a sequence of two minimal nonnegative INTEGERs r and s, each in 1...n.
  (test/cli/std_ecdsa_exercise.iyi)
* ecdsa.5 Malformed signatures or failed equations return false. Valid high-s
  and low-s signatures are both accepted; verification does not require low-s
  normalization. (test/cli/std_ecdsa_exercise.iyi)
* ecdsa.6 This module contains no signing or private key API and its public
  verification arithmetic is variable-time. Key objects retain tape-backed
  coordinates and curve data; retained copies and borrowed inputs follow SPEC
  1.5 and SPEC 3.2.
  <!-- todo: Needs proof -->

## eiy

Eiy translates embedded iyi templates to source and compiles template macros
at their call sites.

* eiy.1 The supported Crystal ECR-style tags are <%= expression %> for
  printing to_s, <% code %> for source, <%# comment %> for ignored text and
  <%% ... %> for literal tag text. It does not HTML-escape output.
  (test/cli/std_eiy_exercise.iyi)
* eiy.2 A leading <%- drops preceding indentation when the tag is first on its
  line; -%> drops following line whitespace and the line end. Other literal
  bytes are preserved. (test/cli/std_eiy_exercise.iyi)
* eiy.3 Lexer and TapeLexer return token values, kinds, trim information and
  character positions with lines and columns starting at one. Unterminated
  tags are errors; next_token? returns nil and error describes the failure.
  (test/cli/std_eiy_exercise.iyi)
* eiy.4 process_string translates a template to code writing through the
  selected output name, default __io__. It quotes literal text safely,
  including interpolation characters and non-UTF-8 bytes; builder forms append
  generated source. (test/cli/std_eiy_exercise.iyi)
* eiy.5 process_string? and process_file? return nil for malformed templates
  while other forms panic with position information. A file read failure uses
  File.read's failure rather than becoming a malformed-template result.
  (test/cli/std_eiy_exercise.iyi)
* eiy.6 embed splices generated source printing to the supplied output; render
  collects a String and def_to_s defines stream and String forms. locate
  resolves relative template paths beside the caller and leaves absolute paths
  absolute. (test/cli/std_eiy_exercise.iyi)
* eiy.7 The eiy/process helper accepts caller, template and output name, reads
  the resolved template and prints generated source; missing arguments or
  translation errors refuse compilation at the macro.
  (test/cli/std_eiy_exercise.iyi)
* eiy.8 Lexers borrow template text. Buffer owns its builder, generated code
  and rendered text follow SPEC 1.5, and output targets need a print method.
  Views into lexer input obey SPEC 3.2.
  <!-- todo: Needs proof -->

## enum

This module extends prelude enums with numeric conversions, iteration and
checked parsing.

* enum.1 Numeric conversions delegate to the member's underlying integer
  conversion. Addition and subtraction step the numeric value and may return a
  value with no declared member; xor combines member bits.
  (test/cli/std_enum_exercise.iyi)
* enum.2 Comparison orders underlying values, clone returns self and stream
  text and inspection match their String forms.
  (test/cli/std_enum_exercise.iyi)
* enum.3 from_value and parse return the result of their question forms or
  panic naming the rejected number or text. Parsing retains the prelude's
  lenient name comparison. (test/cli/std_enum_exercise.iyi)
* enum.4 each visits declared values in declaration order. For flags enums it
  omits synthesized None and All; valid? accepts an individual member or None
  and refuses undeclared combinations and All.
  (test/cli/std_enum_exercise.iyi)

## enumerable

Enumerable supplies eager collection operations from an ordered each. Its
associated Elem type determines the elements returned.

* enumerable.1 Traversal, conversion and indexed traversal follow each order;
  size counts yielded elements, and empty? stops at the first element.
  (test/cli/std_exercise.iyi)
* enumerable.2 all?, any?, none? and one? test the stated number of matches and
  short-circuit when decided; all? and none? are true on an empty input.
  (test/cli/std_exercise.iyi)
* enumerable.3 find and index return the first match or nil; first? returns nil
  on empty input, while first panics with "first of an empty collection".
  (test/cli/std_exercise.iyi)
* enumerable.4 map, flat_map, indexed mapping, select, reject and partition
  retain traversal order. compact_map removes only nil results; find_value
  returns the first non-nil result. (test/cli/std_exercise.iyi)
* enumerable.5 take and skip reject negative counts; their while forms stop
  taking or skipping at the first false predicate. first(n) is take(n).
  (test/cli/std_exercise.iyi)
* enumerable.6 reduce folds left from its initial value; reduce? starts at the
  first element and returns nil on empty input. accumulate returns successive
  accumulator values, excluding the initial value. (test/cli/std_exercise.iyi)
* enumerable.7 Comparable extrema retain the first equal extremum. Nilable
  extrema return nil on empty input; plain extrema panic. The by forms return
  elements and the of forms return mapped values. (test/cli/std_exercise.iyi)
* enumerable.8 sum and product start at Num.zero and Num.one, including on empty
  input. sum_by adds mapped values from the mapped type's zero; sorted returns
  ascending elements. (test/cli/std_exercise.iyi)
* enumerable.9 Tally operations count equal hash keys; group_by keeps each group
  in input order. index_by and to_h keep the last value for a repeated key;
  destination overloads update the supplied hash. (test/cli/std_exercise.iyi)
* enumerable.10 Slices include a short last slice; consecutive windows include
  only full windows; groups pad the last group with the supplied filler. Slice,
  window, group and step sizes must be positive. (test/cli/std_exercise.iyi)
* enumerable.11 zip returns one pair per receiver element and panics if the
  other input is shorter; cycle repeats the sequence n times, and join prints
  elements separated by the given text without a trailing separator.
  (test/cli/std_exercise.iyi)
* enumerable.12 New result containers and joined text use the caller destination
  (SPEC 1.5); their elements retain borrowed roots rather than receiving a deep
  copy.
  <!-- todo: Needs proof -->

## env

ENV reads and changes the process environment. Iteration snapshots the table
before yielding, so deleting yielded names does not skip later entries.

* env.1 [] and fetch without a fallback panic for an absent name; []? returns
  nil. fetch with a value or block uses it only when the name is absent; an
  empty value is present. (test/cli/std_env_exercise.iyi)
* env.2 Assignment replaces a value and returns it; assignment of nil deletes.
  delete returns the old value or nil and removes every occurrence of the name;
  clear deletes all enumerated names. (test/cli/std_env_exercise.iyi)
* env.3 Writes and deletion reject empty names, names containing = or NUL, and
  values containing NUL. Reads reject those invalid names as well.
  (test/cli/std_env_exercise.iyi)
* env.4 each, key and value iteration use one snapshot. keys and values return
  arrays; size and empty? describe the enumerated entries.
  (test/cli/std_env_exercise.iyi)
* env.5 Read values are copied onto the caller tape. to_h writes names and
  values as views of its caller-supplied table builder into the supplied hash.
  POSIX writes retain copied entries and tables on Program.tape.
  <!-- todo: Needs proof -->

## errno

Errno names platform error numbers and gives them fixed English messages.

* errno.1 Named values follow Darwin numbers on macOS and Linux numbers
  otherwise; EAGAIN and EWOULDBLOCK are aliases.
  (test/cli/std_errno_exercise.iyi)
* errno.2 message returns the module's English sentence, including "Success" for
  NONE and "Unknown error" for an unnamed value; it does not consult a locale.
  (test/cli/std_errno_exercise.iyi)
* errno.3 Message literals require no caller cleanup. The table describes errno
  values, rather than translating socket or file error result types.
  <!-- todo: Needs proof -->

## file

File extends the prelude with metadata, paths, links, temporary files and
descriptor positioning and locking.

* file.1 info returns size, type, permission and special bits, owner/group,
  identity and timestamps; it follows symlinks by default. info? returns nil
  when stat fails; info panics. Nonfollowing inspection describes the link
  itself. (test/cli/std_file_exercise.iyi)
* file.2 Type and permission predicates inspect the recorded kind and bits; path
  access predicates ask the platform. Missing paths are false for type, access
  and empty? queries. same? compares file identities; same_content? compares
  whole regular-file contents. (test/cli/std_file_exercise.iyi)
* file.3 touch creates a missing file and sets access and modification times to
  now when time is zero, otherwise to the supplied Unix second; touch? reports
  success as Bool. (test/cli/std_file_exercise.iyi)
* file.4 rename moves or replaces according to the platform; link and symlink
  make hard and symbolic links. readlink returns the stored link text; real_path
  resolves the existing path and symlinks. Refused operations panic with the
  path. (test/cli/std_file_exercise.iyi)
* file.5 chmod applies permission bits, chown sets numeric ownership, and
  truncate resizes a file, defaulting to zero bytes. OS failures panic rather
  than being ignored. (test/cli/std_file_exercise.iyi)
* file.6 Basename, dirname, extension, expansion and joining use Path's rules.
  match? recognizes segment-local * and ?, ** segments, bracket classes, escaped
  characters and brace alternatives nested to ten levels.
  (test/cli/std_file_exercise.iyi)
* file.7 read_lines reads the whole file and returns line views without LF or
  its preceding CR; a final unpaired CR is retained. each_line streams the same
  lines and closes its file on every exit. (test/cli/std_file_exercise.iyi)
* file.8 tempfile creates an exclusive empty file with owner-only permissions,
  using TMPDIR, TEMP, TMP then the platform temporary directory. The returned
  path remains until deleted; the block form deletes it on exit if it still
  exists. (test/cli/std_file_exercise.iyi)
* file.9 seek flushes output, adjusts Current for buffered unread bytes and
  resets the read buffer; pos includes buffered output and excludes unread
  input. Closed streams and failed seeks panic. (test/cli/std_file_exercise.iyi)
* file.10 Shared locks permit multiple holders; exclusive locks exclude them.
  Waiting locks park between retries and may return Cancelled; try forms return
  Bool. Block forms unlock on every exit; closing a descriptor releases its
  locks. (test/cli/std_file_exercise.iyi)
* file.11 Path text and metadata results use the caller destination (SPEC 1.5).
  File handles opened by callers require explicit close or the prelude's block
  cleanup; returned path strings own no handle.
  <!-- todo: Needs proof -->

## file_utils

FileUtils copies, removes, moves and compares files and directory trees using
File and Dir.

* file_utils.1 cp copies bytes and permission bits, follows a source symlink and
  accepts a directory destination under the source basename; it rejects
  directories and copying a file onto itself. Owners and timestamps are not
  copied. (test/cli/std_file_utils_exercise.iyi)
* file_utils.2 cp_r copies directory contents and permission bits, recreates
  symlinks without following them, and rejects special files and a destination
  inside the source tree. A source link with a trailing separator names its
  directory target. (test/cli/std_file_utils_exercise.iyi)
* file_utils.3 rm_r removes files, links and trees without following links,
  including links with trailing separators. A missing path panics; rm_rf accepts
  it but still reports other removal failures.
  (test/cli/std_file_utils_exercise.iyi)
* file_utils.4 mv renames on one device and otherwise copies completely before
  removing the source. A directory destination receives the source basename.
  Trailing separators on source links are removed so the link itself moves.
  (test/cli/std_file_utils_exercise.iyi)
* file_utils.5 compare_file returns byte equality, stops at a differing piece,
  and skips content reads for unequal sizes or identical file identities.
  (test/cli/std_file_utils_exercise.iyi)
* file_utils.6 Copies and comparisons reuse 64 KiB buffers rather than loading
  whole files; internally opened descriptors are closed. Failures panic with
  paths and the refused operation; partial destination work is not rolled back.
  (test/cli/std_file_utils_exercise.iyi)

## fileserver

FileServer answers file requests into an existing HTTP Outgoing. Its caching and
single-range behaviour implement the stated parts of RFC 9110.

* fileserver.1 GET and HEAD are accepted case-insensitively; other methods
  answer 405 with Allow: GET, HEAD. A missing or nonregular file answers 404.
  (test/ris/check.sh)
* fileserver.2 The path is percent-decoded and must begin with /; NUL, backslash
  and any .. segment answer 404. Symlinks below root are followed, including
  ones naming files outside root; this is not a symlink sandbox.
  (test/ris/check.sh)
* fileserver.3 A directory without its trailing slash redirects with 301,
  preserving its query; otherwise its configured index, index.html by default,
  is served with MIME-derived type and applicable UTF-8 charset.
  (test/ris/check.sh)
* fileserver.4 Last-Modified and an ETag made from hexadecimal modification time
  and size accompany successful replies. If-None-Match uses weak comparison and
  takes precedence over If-Modified-Since; a match answers 304 without a body or
  content type. (test/ris/check.sh)
* fileserver.5 One bytes range, including a suffix, answers 206 with Content-
  Range; a range starting beyond the file answers 416. Invalid, multiple or
  other-unit ranges are ignored. If-Range must match the strong tag or exact
  modification date. (src/std/fileserver.iyi)
* fileserver.6 GET reads the selected bytes into res.body; HEAD only sets the
  length. The default maximum is 16 MiB and a supplied maximum is capped at 120
  MiB. Larger selections or a file shortened during reading answer 500.
  (test/ris/check.sh)
* fileserver.7 All response text goes into caller-owned response storage;
  internally opened files are closed and whole-file buffering is bounded by the
  selected maximum.
  <!-- todo: Needs proof -->

## float

The float module supplies Float32 operations and extends Float64 with
predicates, constants, ordering and remainder operations.

* float.1 Float32 arithmetic rounds to Float32; mixed arithmetic follows the
  receiver's declared result type, with integer/Float32 arithmetic producing
  Float32 and integer division by an integer producing Float64. Integer
  comparisons remain exact. (test/cli/std_float_exercise.iyi)
* float.2 nan?, finite? and infinite? distinguish NaN, finite numbers and signed
  infinities; infinite? returns -1, 1 or nil. Constants describe each format's
  finite bounds, epsilon, minimum positive normal, NaN and infinity.
  (test/cli/std_float_exercise.iyi)
* float.3 <=> orders NaN after all numbers and treats two NaNs as equal for
  ordering; ordinary floating equality retains IEEE NaN behaviour.
  (test/cli/std_float_exercise.iyi)
* float.4 Remainder uses truncated division and the dividend sign; % uses floor
  division and the divisor sign, including zero. Zero divisors panic for
  remainder, % and //. (test/cli/std_float_exercise.iyi)
* float.5 Integer conversion truncates before checking the destination range and
  refuses NaN and infinity. Narrowing Float64 to Float32 overflows to signed
  infinity and may underflow to signed zero. (test/cli/std_float_exercise.iyi)
* float.6 Float32 abs, floor, ceil, round, trunc and integer powers return
  Float32; rounding by digits and rounding mode delegate to Float64 before
  narrowing. (test/cli/std_float_exercise.iyi)
* float.7 Float32 text is the shortest decimal that reads back to the same
  single, including a signed zero; text uses the caller destination (SPEC 1.5).
  (test/cli/std_float_exercise.iyi)

## format

Formatting supplies sprintf, printf, String.format and String percent
formatting. It implements a defined subset of POSIX printf with binary and
inspected-value extensions.

* format.1 Formats accept flags -, +, space, 0 and #, decimal width and
  precision, and conversions s, p, c, d, i, u, x, X, o, b, f, e, E, g and G; %%
  writes one percent without consuming an argument. Positional, length and star
  fields are not implemented. (test/cli/format_exercise.iyi)
* format.2 Arguments may be variadic, a tuple or an array; too few or too many
  arguments panic, as do unknown conversions and incomplete directives. Width
  and precision larger than Int32 panic with the field named.
  (test/cli/format_exercise.iyi)
* format.3 Width is a minimum, left alignment adds trailing spaces and zero
  padding goes after signs and prefixes. Integer precision sets a minimum digit
  count; zero at precision zero has no digits. Alternate bases use 0x, 0X, 0o
  and 0b. (test/cli/format_exercise.iyi)
* format.4 s prints to_s and p prints inspect; string width and precision count
  characters. c accepts a Char or Unicode scalar integer and rejects surrogates
  and out-of-range integers. (test/cli/format_exercise.iyi)
* format.5 Floating precision uses exact decimal digits rounded halfway to even.
  f uses fractional places, e/E scientific notation, and g/G significant digits
  and the implemented C-style exponent threshold, trimming zeros unless
  alternate form is requested. (test/cli/format_exercise.iyi)
* format.6 f and e/E permit at most 400 fractional places, and g/G at most 401
  significant digits; nonnumeric values used for numeric conversions panic.
  Nonfinite floats have explicit text forms, while truncating one for integer
  formatting is refused.
  <!-- todo: Needs proof -->
* format.7 String results use SPEC 1.5; builder overloads append without
  clearing existing text. printf writes to STDOUT without adding a newline and
  leaves it open. (test/cli/format_exercise.iyi)

## gc

This inherited collector interface is unavailable to ris user programs.

* gc.1 Importing std/gc in a ris build is refused under SPEC 7.1, naming tape
  values and copy_to(owner) as the replacement.
  <!-- todo: Needs proof -->

## heap

Heap is a mutable binary min-heap over Comparable elements.

* heap.1 push inserts one element; peek returns the least element without
  removal, and pop removes and returns it according to <=>. Equal elements have
  no promised relative order. (test/cli/std_heap_exercise.iyi)
* heap.2 A new heap is empty; size counts insertions minus removals. Empty peek
  and pop panic with "peek of an empty heap" and "pop of an empty heap",
  respectively.
  <!-- todo: Needs proof -->
* heap.3 The heap owns its tape array; insertion stores element values with
  their existing roots. Retention follows SPEC 1.7 and 3.2.
  <!-- todo: Needs proof -->

## hpack

hpack implements HTTP/2 header compression under RFC 7541. Header fields
preserve order and their indexing mode.

* hpack.1 The static table has RFC 7541 Appendix A's 61 entries. Global indices
  are one-based, followed by newest-first dynamic entries; absent lookups return
  nil or the search sentinel zero. (test/cli/std_hpack_exercise.iyi)
* hpack.2 Dynamic entry size is name bytes plus value bytes plus 32. Adding
  evicts oldest entries until it fits; an entry larger than the maximum clears
  the table without insertion. Negative or above-settings table sizes are
  refused. (test/cli/std_hpack_exercise.iyi)
* hpack.3 Prefix integers support widths 1 through 8; decoding returns the value
  and next offset or HpackError for bounds, truncation or UInt64 overflow.
  Encoding invalid prefix widths panics. (test/cli/std_hpack_exercise.iyi)
* hpack.4 Raw and Huffman strings implement RFC 7541 section 5 and Appendix B.
  Huffman decoding refuses EOS in data, padding longer than seven bits and
  padding other than the EOS all-one prefix. (test/cli/std_hpack_exercise.iyi)
* hpack.5 Decoding handles indexed fields and all three literal modes, changing
  the dynamic table only for incremental indexing. Invalid indices, truncated
  strings and late or excessive table-size updates return HpackError.
  (test/cli/std_hpack_exercise.iyi)
* hpack.6 Decoded header counts and sizes are bounded, defaulting to 1000 fields
  and 65536 octets with 32 overhead octets per field; exceeding either returns
  HpackError. (test/cli/std_hpack_exercise.iyi)
* hpack.7 Encoding respects never-indexed and without-indexing fields; table-
  size changes emit the interval minimum before the final size when needed.
  Huffman use is configurable and may be overridden per call.
  (test/cli/std_hpack_exercise.iyi)
* hpack.8 encode and encode_on_tape build wire text in the caller destination.
  Dynamic tables copy names and values into owned SlicePool runs, freeing runs
  on eviction; table views must not be retained across eviction without SPEC
  1.7. (src/std/hpack.iyi)
* hpack.9 TapeHeaders has fixed field capacity and panics when full; keep copies
  and deduplicates text in list-owned storage. decode into it appends decoded
  fields using that storage, independent of dynamic-table eviction.
  (src/std/hpack.iyi)

## hpke

hpke implements RFC 9180 public-key encryption, authenticated contexts and
secret export. Randomness is always supplied by the caller.

* hpke.1 Suites combine DHKEM X25519/SHA256, P-256/SHA256 or P-384/SHA384 with
  HKDF SHA256, SHA384 or SHA512 and AES128-GCM, AES256-GCM, ChaCha20-Poly1305 or
  export-only AEAD. Unknown IDs return HpkeError; P-521, X448 and post-quantum
  KEMs are not supported. (test/cli/std_hpke_exercise.iyi)
* hpke.2 PSK and PSK ID select PSK mode; sender authentication selects auth
  mode, with both selecting auth_psk. Supplying only one PSK input, a PSK
  shorter than 32 bytes or a key from another KEM panics.
  (test/cli/std_hpke_exercise.iyi)
* hpke.3 DeriveKeyPair follows RFC 9180 section 7.1.3, requiring at least 32
  input bytes, or 48 for P-384. Encapsulation derives an ephemeral key from
  caller randomness with the same minimum; candidate exhaustion panics.
  (test/cli/std_hpke_exercise.iyi)
* hpke.4 Serialized X25519 keys are 32 bytes; P-256 and P-384 public keys are
  uncompressed 65- and 97-byte points and private scalars are 32 and 48 big-
  endian bytes. Input validation returns HpkeError for wrong lengths, invalid
  points and all-zero X25519 agreement. (test/cli/std_hpke_exercise.iyi)
* hpke.5 Declare HpkeSender or HpkeRecipient as a named owner and call setup;
  suite.sender and suite.recipient are compile-time refusals naming that form.
  Setup resets the sequence to zero; seal and open bind info, AAD and selected
  mode. (test/cli/std_hpke_exercise.iyi)
* hpke.6 Each successful seal or open advances the sequence once; authentication
  failure returns HpkeError and leaves it unchanged. Sequence 2^96 - 1 is never
  used; advance_to permits only forward movement up to that boundary.
  (test/cli/std_hpke_exercise.iyi)
* hpke.7 Export derives 0 through 255 hash-length bytes bound to
  exporter_context; larger or negative lengths panic. Export-only contexts may
  export but seal and open panic. Single-shot operations follow the same
  schedule and errors. (test/cli/std_hpke_exercise.iyi)
* hpke.8 Message inputs are borrowed bytes. Ciphertexts and plaintexts are
  caller-tape Strings, while keys, encapsulations and exports are tape arrays.
  Context setup refills owned buffers; secrets are not explicitly wiped.
  <!-- todo: Header claims heap storage and obsolete context factories. -->
  <!-- todo: Needs proof -->

## html

HTML escapes markup characters and reads numeric and named character references.
Its named table is the HTML 4.01 set with XML apos, not the full HTML5 table.

* html.1 escape replaces &, <, >, double quote and apostrophe by &amp;, &lt;,
  &gt;, &quot; and &#39;, copying every other byte unchanged.
  (test/cli/std_html_exercise.iyi)
* html.2 unescape reads decimal and hexadecimal numeric references with an
  optional semicolon; invalid scalar values, zero and values beyond Unicode
  become U+FFFD, and C1 references use the implemented HTML replacement table.
  (test/cli/std_html_exercise.iyi)
* html.3 Named decoding chooses the longest known prefix. Only legacy names may
  omit a semicolon; unknown references and digitless numeric references retain
  their original bytes. (test/cli/std_html_exercise.iyi)
* html.4 String results use the caller destination (SPEC 1.5); escape may return
  the original view when unchanged. The builder overload appends directly and
  the IO overload writes the escaped text without closing the stream.
  <!-- todo: Needs proof -->

## http

http implements HTTP clients, servers and streaming bodies over sockets and TLS.
It supports HTTP/1.0 and HTTP/1.1 message handling and the implemented HTTP/2
subset of RFC 9113.

* http.1 Requests accept http and https URLs with DNS names, IPv4 or bracketed
  IPv6 hosts. HTTPS verifies the peer for the origin using configured or system
  roots; errors are Cancelled, SocketError or HTTPError values.
  (test/cli/std_http_exercise.iyi)
* http.2 request and method helpers return a fully loaded Response. open gives a
  live streamed response to a block and returns its result, closing or releasing
  the exchange on exit; body_io exposes bounded pieces and read_all_into appends
  to caller storage. (test/cli/std_http_exercise.iyi)
* http.3 String request bodies use Content-Length and IO bodies stream chunked
  under HTTP/1.1. Response bodies honor content length, chunk framing or close
  framing; HEAD and bodiless statuses have no payload. Truncated and malformed
  framing returns HTTPError. (test/cli/std_http_exercise.iyi)
* http.4 Header names compare case-insensitively. Repeated values join with ", "
  for ordinary lookup while header_values retains individual lines, including
  Set-Cookie. Interim responses are skipped before the final response.
  (test/cli/std_http_exercise.iyi)
* http.5 Redirects 301, 302, 303, 307 and 308 follow the implemented browser
  method rewrite rules, with ten redirects by default. Cross-host redirects drop
  caller credentials and cookies; an optional cookie store receives Set-Cookie
  and supplies matching request cookies. (test/cli/std_http_exercise.iyi)
* http.6 Automatic response decompression supports gzip, deflate and zstd unless
  disabled or the caller supplies Accept-Encoding. zstd windows are bounded to 8
  MiB under RFC 9659; corrupt compressed data returns HTTPError.
  (test/cli/std_http_exercise.iyi)
* http.7 HTTPClient reuses eligible idle connections, bounds them by idle, four
  by default, and requires close to release them. It bounds cached TLS tickets
  per origin and in total, defaults four and 256, and supports at most 64 ticket
  origins; invalid capacities or negative timeouts panic.
  (test/cli/std_http_exercise.iyi)
* http.8 A client may use its own resolver and TLS configuration. HTTPS service-
  record use is opt-in; configured record endpoints and ECH/ALPN bind connection
  and ticket reuse to the configuration under which they were made.
  <!-- todo: Needs proof -->
* http.9 HTTP proxy URLs or host:port endpoints use absolute-form requests for
  HTTP and CONNECT for HTTPS; proxy credentials go only to the proxy. TLS
  proxies and SOCKS are refused; a failed CONNECT returns HTTPError with its
  status. (test/cli/std_http_exercise.iyi)
* http.10 proxy_for is pure: it selects by URL scheme, bypasses localhost and
  loopback, and matches no_proxy domains, suffixes, wildcard, addresses, CIDR
  ranges and optional ports. Environment reads belong to http_proxy.
  (test/cli/std_http_exercise.iyi)
* http.11 Server.answer builds handlers per serving task from checked config
  copies. Incoming exposes request method, path, query, fields and body;
  Outgoing takes status, fields and body, a stream, an IO send or an upgrade.
  (test/cli/std_http_exercise.iyi)
* http.12 Request heads over 1 MiB answer 431 and bodies over 64 MiB answer 413;
  malformed requests answer 400 and close. Streamed request mode defers body
  reads to the handler and drains at most 1 MiB left unread before closing.
  (test/cli/std_http_exercise.iyi)
* http.13 Outgoing status and headers are checked before transmission: invalid
  status, field name or control-containing value panics. Known lengths are
  framed explicitly; streamed unknown lengths use the protocol's streaming
  framing. (test/cli/std_http_exercise.iyi)
* http.14 With compression enabled, eligible whole bodies negotiate zstd or gzip
  using accepted qualities, preferring zstd on a tie; streamed answers use gzip.
  Already encoded or unsuitable media are not compressed.
  (test/cli/std_http_exercise.iyi)
* http.15 TLS server configuration enables server handshakes and optional client
  certificates; Incoming exposes the presented chain. Session resumption is
  observable, but neither client nor server sends or accepts HTTP early data.
  (test/cli/std_http_exercise.iyi)
* http.16 Connections reuse HTTP/1.1 sequentially and close according to framing
  and Connection. Graceful shutdown shuts the write half and drains inbound
  bytes for at most ten seconds and 64 MiB with at most a one-second gap;
  cancellation ends serving. (test/cli/std_http_exercise.iyi)
* http.17 HTTP/2 is selected by the cleartext preface, TLS ALPN h2 or client
  prior knowledge. Frame handling enforces stream state, settings, flow control
  and header validation; HPACK encodes field blocks and protocol violations
  cause stream or connection errors. (test/cli/http2_exercise.iyi)
* http.18 HTTP/2 does not offer server push, HTTP/1 upgrade negotiation or RFC
  8441 WebSockets. WebSocket upgrade uses HTTP/1.1; HTTP/1.1 request pipelining
  and zstd streaming output are not provided. (test/cli/http2_exercise.iyi)
* http.19 Pure format and parse helpers build or read message text without
  opening connections; parse_head delegates to http_head. Field parsing accepts
  obsolete folding only when requested, and content-length and chunk helpers
  reject invalid framing. (test/cli/std_http_exercise.iyi)
* http.20 Multipart accepts boundaries of 1 through 70 bytes and reuses a
  caller-owned Part; requesting the next part drains the previous one. Part
  heads are limited to 16384 bytes; read_all enforces its supplied body limit
  and returns HTTPError on overflow. (test/cli/std_http_exercise.iyi)
* http.21 MultipartBuilder writes ordered form fields and files with quoted
  disposition parameters and a closing boundary. Automatic boundaries derive
  deterministically from content hashes and avoid body collisions; explicit
  colliding boundaries and line breaks in part types are refused.
  (test/cli/std_http_exercise.iyi)
* http.22 cookie_pairs reads semicolon-separated name/value pairs, removes
  surrounding value quotes and keeps the first duplicate name under RFC 6265
  section 4.2. Coding negotiation reads names and qualities with wildcard
  fallback. (test/cli/std_http_exercise.iyi)
* http.23 Incoming strings borrow request bytes and expire with the request
  tape; Outgoing writes into caller-owned response storage. Retaining a body or
  field requires SPEC 1.7, and caller-created streaming/client resources require
  close.
  <!-- todo: Needs proof -->

## http_head

http_head parses HTTP/1 request heads without transport, clock or environment
initialization.

* http_head.1 parse_head returns nil until the terminal blank line arrives,
  unless complete asks it to treat the available text as a complete head;
  success reports body_start after that separator. Leading CRLF empty lines are
  ignored per RFC 9112 section 2.2. (test/cli/std_http_exercise.iyi)
* http_head.2 The method must be a nonempty token, the target nonempty and
  control-free, and version HTTP/1.0 or HTTP/1.1. Malformed heads return
  HeadError with status 400. (test/cli/std_http_exercise.iyi)
* http_head.3 Fields require a token name and colon, trim surrounding space and
  tab and reject control characters. Obsolete folded lines are refused. HTTP/1.1
  requires exactly one Host and HTTP/1.0 permits at most one.
  (test/cli/std_http_exercise.iyi)
* http_head.4 Host must be nonempty and consist only of the module's allowed
  host bytes.
  <!-- todo: Empty Host passes host? because its byte loop is empty. -->
  <!-- todo: Needs proof -->
* http_head.5 A head exceeding MAX_HEAD, 1048576 bytes, returns status 431
  whether it arrives whole or in pieces.
  <!-- todo: Complete heads bypass the size-limit branch. -->
  <!-- todo: Needs proof -->
* http_head.6 Field lookup is ASCII case-insensitive and returns the first value
  or nil. each_field joins repeated values with ", " in first-name order;
  field_held skips repeats and writes joined text into the supplied builder.
  (test/cli/std_http_exercise.iyi)
* http_head.7 content_length returns zero when absent and nil for invalid or
  inconsistent decimal lengths, comparing repeated list members after saturation
  under RFC 9110 section 8.6; oversized lengths saturate at 2147483648.
  (test/cli/std_http_exercise.iyi)
* http_head.8 Successful request-line and field strings view input bytes; fields
  are written into the caller array, cleared when field parsing begins. Joined
  text uses caller storage; retention follows SPEC 1.7.
  <!-- todo: Needs proof -->

## http_proxy

HTTPProxy selects the environment-named proxy for an HTTP URL. Routing itself is
delegated to HTTP.proxy_for.

* http_proxy.1 from_env reads http_proxy, https_proxy and no_proxy, preferring a
  set lowercase name over its uppercase spelling even when the lowercase value
  is empty. (test/cli/std_http_proxy_exercise.iyi)
* http_proxy.2 When REQUEST_METHOD is set, uppercase HTTP_PROXY is ignored to
  prevent CGI header injection. Selection returns nil when HTTP.proxy_for
  chooses a direct connection. (test/cli/std_http_proxy_exercise.iyi)
* http_proxy.3 Returned proxy text follows ENV's caller-tape lifetime; this
  module opens no connection and owns no resource to close.
  <!-- todo: Needs proof -->

## idna

idna converts internationalized domain labels with Punycode and a bounded
IDNA2008 profile. It is pure computation over Unicode data.

* idna.1 Punycode implements RFC 3492 encoding and decoding of Unicode code
  points; decoding returns PunycodeError for non-ASCII input, invalid base-36
  digits, incomplete or overflowing numbers and non-scalar results.
  (test/cli/std_idna_exercise.iyi)
* idna.2 Host conversion splits on ASCII dot and U+3002, U+FF0E and U+FF61,
  keeps one trailing dot and lowercases ASCII letters. Each ASCII label is at
  most 63 bytes and the full name at most 253 excluding the trailing dot.
  (test/cli/std_idna_exercise.iyi)
* idna.3 ASCII labels accept letters, digits, hyphens and underscores; edge
  hyphens and positions three/four containing -- are refused except in xn--
  labels. An A-label must decode to a valid non-ASCII U-label.
  (test/cli/std_idna_exercise.iyi)
* idna.4 U-labels must already be NFC, must not start with a combining mark and
  must satisfy RFC 5892 PVALID or supported CONTEXTO checks. property derives
  the RFC classification from the Unicode tables.
  (test/cli/std_idna_exercise.iyi)
* idna.5 No UTS #46 compatibility mapping or transitional processing is applied.
  CONTEXTJ joiners are refused because joining and Virama properties are absent;
  failures return IdnaError naming the offending label or code point.
  (test/cli/std_idna_exercise.iyi)
* idna.6 IDNA2008 host conversion must also enforce the RFC 5893 Bidi rule.
  <!-- todo: Bidi_Class is absent; invalid RTL labels are accepted. -->
  <!-- todo: Needs proof -->
* idna.7 Returned names use the caller destination (SPEC 1.5); inputs are
  borrowed and no resolver, clock or resource is opened.
  <!-- todo: Needs proof -->

## indexable

Indexable supplies indexed sequence operations from size and unsafe_fetch.
IndexableMutable adds operations through unsafe_put.

* indexable.1 Indices are zero-based and negative indices count from the end. []
  panics outside the sequence, naming the original index and size; []? returns
  nil and fetch uses its default or block. (test/cli/std_indexable_exercise.iyi)
* indexable.2 each and each_index traverse forwards, reverse_each backwards.
  first and last panic on empty input while their ? forms return nil.
  Implementing Indexable alone does not declare Enumerable.
  (test/cli/std_indexable_exercise.iyi)
* indexable.3 index and rindex return the first and last matching index or nil.
  bsearch and bsearch_index find the first true position for a monotone
  predicate or return nil. (test/cli/std_indexable_exercise.iyi)
* indexable.4 values_at preserves requested order and applies checked indexing.
  Slices include a short last slice and consecutive windows include only full
  windows; sizes must be positive. (test/cli/std_indexable_exercise.iyi)
* indexable.5 sample returns a random element and refuses an empty sequence.
  sample(n) refuses negative n, samples distinct positions up to the sequence
  size and shuffles them; a supplied Random controls selection.
  (test/cli/std_indexable_exercise.iyi)
* indexable.6 dig and dig? use checked and nilable indexing. equals? compares
  size and corresponding elements, optionally with a predicate. join prints
  separated elements; to_a copies slots and hash mixes elements in order.
  (test/cli/std_indexable_exercise.iyi)
* indexable.7 update returns the replacement value; swap checks both indices
  before changing either. Reverse and rotation mutate in place, rotation moving
  element n to the front modulo size; empty rotation does nothing.
  (test/cli/std_indexable_exercise.iyi)
* indexable.8 fill replaces all elements, a checked offset/count window or each
  index with its block result; a negative count or window beyond the end panics
  before writing. (test/cli/std_indexable_exercise.iyi)
* indexable.9 Result arrays and text use the caller destination (SPEC 1.5);
  copied slots preserve element roots. In-place changes retain the receiver's
  storage.
  <!-- todo: Needs proof -->

## ini

INI reads and writes sectioned configuration text. RisIni keeps sections and
assignments in their first-appearance order.

* ini.1 Parsing accepts LF or CRLF lines, a leading UTF-8 BOM, blank lines and
  whole-line # or ; comments after leading ASCII whitespace. Keys before a
  header belong to section "". (test/cli/std_ini_exercise.iyi)
* ini.2 A section ends at ]; any bytes after ] are refused. Assignment splits at
  the first = and trims key and value whitespace, retaining later equals signs;
  repeated headers continue a section and repeated keys replace its value in
  place. (test/cli/std_ini_exercise.iyi)
* ini.3 Malformed declarations panic with a line and character column. Missing-
  key [] panics, []? returns nil, and section?, each, size and empty? inspect
  stored assignments. (test/cli/std_ini_exercise.iyi)
* ini.4 build writes top-level keys first, then named sections with a trailing
  blank line each; space selects " = " instead of "=". String, builder and IO
  outputs carry the same bytes. (test/cli/std_ini_exercise.iyi)
* ini.5 Building rejects line breaks, ] in section names, empty or ambiguous
  keys, = in keys and leading or trailing whitespace in keys or values; keys
  beginning with a BOM are also refused. (test/cli/std_ini_exercise.iyi)
* ini.6 Parsing borrows String input; names and values view it. IO parsing owns
  the read text on the caller tape. Builder output appends in place, and
  retained documents require SPEC 1.7.
  <!-- todo: Needs proof -->

## int

The int module extends fixed-width signed and unsigned integers through 128 bits
with arithmetic, conversions and bit utilities.

* int.1 Arithmetic returns the declared receiver type and checked overflow
  panics; wrapping & arithmetic retains low bits. Comparisons between integer
  widths and against Float64 compare numeric values exactly.
  (test/cli/std_int_exercise.iyi)
* int.2 Checked integer conversions panic when the result does not fit, nilable
  conversions return nil and unsafe conversions truncate or extend bits. Float
  conversions truncate first, then reject a nonfinite or out-of-range result.
  (test/cli/std_int_exercise.iyi)
* int.3 Integer // and % reject zero divisors. A signed minimum divided by -1
  panics for overflow; its remainder by -1 is zero.
  (test/cli/std_int_exercise.iyi)
* int.4 Negative shift counts reverse direction; shifts at least the type width
  yield zero, except right shifts of negative signed values yield -1. Bit tests
  and counts inspect the fixed-width representation; zero has leading and
  trailing zero counts equal to width. (test/cli/std_int_exercise.iyi)
* int.5 gcd returns a nonnegative common divisor and lcm returns zero when
  either input is zero; unrepresentable results panic. digits rejects negative
  values and bases below 2 and returns least-significant digits first, with [0]
  for zero. (test/cli/std_int_exercise.iyi)
* int.6 to_s accepts bases 2 through 36 and emits a sign and lowercase digits;
  other bases panic. chr accepts Unicode scalar values and rejects surrogates
  and values outside 0 through 0x10FFFF; unsafe_chr bypasses that check.
  (test/cli/std_int_exercise.iyi)
* int.7 Numeric results are values; printed strings and digit arrays use the
  caller destination (SPEC 1.5) and own no external resource.
  <!-- todo: Needs proof -->

## io

io adds byte-stream helpers, adapters, pipes and binary formats to IyiIO. Memory
offers a seekable tape-backed byte stream.

* io.1 read_char returns the next Unicode scalar or nil at EOF and panics on
  malformed, overlong, surrogate, out-of-range or truncated UTF-8. Line helpers
  use read_line semantics; lines stores returned views in the caller text
  builder. (test/cli/std_io_exercise.iyi)
* io.2 IyiIO.copy transfers remaining bytes up to an optional nonnegative limit,
  flushes the destination and returns the byte count without closing either
  stream. << prints a value and returns the receiver.
  (test/cli/std_io_exercise.iyi)
* io.3 Memory copies initial text, starts its cursor at zero, and writes at the
  cursor, overwriting existing bytes or extending the buffer. pos is a byte
  offset bounded by size; rewind resets it and clear resets size and cursor.
  (test/cli/std_io_exercise.iyi)
* io.4 Memory reads advance the cursor and return at most the available bytes;
  EOF is nil for a byte or line and empty text for a byte read. Chomp removes LF
  and a preceding CR but retains a final unpaired CR. Closed reads and writes
  panic. (test/cli/std_io_exercise.iyi)
* io.5 Memory to_s copies all stored bytes into caller-tape text independently
  of the read cursor; read_str appends up to its count into the supplied
  builder, returning zero for nonpositive counts. (test/cli/std_io_exercise.iyi)
* io.6 Reader adapters refuse writes. Sized exposes at most its nonnegative
  limit, counting bytes actually read; Delimited requires a nonempty delimiter,
  consumes it without returning it and leaves its source immediately after it.
  (test/cli/std_io_exercise.iyi)
* io.7 MultiWriter writes and flushes every underlying stream in order and
  refuses reads. Closing it flushes and closes only the adapter, leaving
  underlying streams open. (test/cli/std_io_exercise.iyi)
* io.8 Hexdump writes sixteen bytes per line with an eight-digit hexadecimal
  offset, two groups of eight bytes and printable ASCII between bars, in hexdump
  -C form. (test/cli/std_io_exercise.iyi)
* io.9 ByteFormat encodes and decodes Int32, Int64, UInt64 and UInt8 in little
  or big endian, preserving signed bit patterns. A short input panics;
  NetworkEndian is big endian and SystemEndian follows the target.
  (test/cli/std_io_exercise.iyi)
* io.10 pipe returns pooled reader and writer handles backed by OS pipes on
  supported targets. Reads and writes park when blocked, writer close exposes
  EOF after buffered data, and reader close makes later writes fail without
  SIGPIPE. (test/ris/check.sh)
* io.11 Each pipe end requires explicit close; reused pool slots reject stale
  handles. Other adapters borrow their underlying IO and tape data under SPEC
  3.2, with no ownership transfer or implicit close of the underlying stream.
  <!-- todo: Needs proof -->

## iterator

Iterator supplies consuming pull sequences and lazy adaptors. Stop marks
exhaustion separately from a nil element.

* iterator.1 next yields an element or Stop; nil remains a normal element. each,
  to_a, count and size consume the remaining sequence rather than restarting it.
  (test/cli/std_iterator_exercise.iyi)
* iterator.2 Array iterators visit indices in order, finite ranges respect their
  excluded end and endless ranges count up without an end. A beginless range is
  refused at compile time; hash iterators snapshot keys or values at
  construction. (test/cli/std_iterator_exercise.iyi)
* iterator.3 map, select, reject, compact_map and flat_map pull only as
  demanded; flat_map expands returned arrays in order and compact_map drops only
  nil. (test/cli/std_iterator_exercise.iyi)
* iterator.4 take and first(n) pull at most n elements; skip discards n.
  Negative counts panic when the adaptor is constructed. While forms consume
  through their deciding predicate, and take_while does not yield the first
  false element. (test/cli/std_iterator_exercise.iyi)
* iterator.5 zip ends when either source ends; chain exhausts the first before
  the second. with_index pairs successive elements with an increasing index
  starting at the supplied offset. (test/cli/std_iterator_exercise.iyi)
* iterator.6 Slices include a short last slice and consecutive windows include
  only full windows. step yields the first then each nth element; their sizes
  must be positive. (test/cli/std_iterator_exercise.iyi)
* iterator.7 cycle caches the first pass and replays it indefinitely or for n
  passes; an empty source or a nonpositive finite repeat count yields no
  elements. (test/cli/std_iterator_exercise.iyi)
* iterator.8 Predicates and find stop when decided. first, min and max panic
  when exhausted; their ? forms return nil. Reduction proceeds left to right;
  empty sum and product return Num.zero and Num.one.
  (test/cli/std_iterator_exercise.iyi)
* iterator.9 Adaptors retain their source and borrowed roots; reference-type
  sources share progress. Materialized arrays and cycle caches live on their
  owning tape under SPEC 1.5 and 3.2.
  <!-- todo: Needs proof -->

## json

json reads RFC 8259 documents and writes structured JSON text. It exposes
indexed documents, dynamic values, pull parsing and typed conversions.

* json.1 Parsing maps null to Nil, booleans to Bool, fitting integer literals to
  Int64, other numbers to finite Float64, strings to decoded String, arrays to
  Any elements and objects to ordered RisJsonFields. Integer -0 becomes zero.
  (test/cli/std_json_exercise.iyi)
* json.2 parse and document panic with line and column on malformed input; their
  ? forms return nil. Readers reject BOM, invalid UTF-8, raw string controls,
  bad escapes, lone surrogates, leading zeros, trailing commas, extra root text,
  duplicate keys, overflowed numbers and nesting beyond 256.
  (test/cli/std_json_exercise.iyi)
* json.3 Document root index is zero; tree indices identify values, child lookup
  preserves document order and object lookup uses decoded keys. Any wraps a
  document position and exposes kind and checked typed accessors.
  (test/cli/std_json_exercise.iyi)
* json.4 Wrong-kind access panics and nilable accessors return nil; Int32
  conversion also checks range. as_f accepts integer and float values. Array and
  object indexing, size and dig inspect the referenced value; dig? returns nil
  on a missing or wrong-kind path. (test/cli/std_json_exercise.iyi)
* json.5 Any equality compares values recursively, treats equivalent integer and
  float values equally and ignores object-key order; hashes agree for equal
  values. Serialization retains object insertion order.
  (test/cli/std_json_exercise.iyi)
* json.6 PullParser exposes successive scalar and container events, source
  locations and raw values. Typed reads advance after checking the current
  event; skip consumes a whole value, on_key skips other fields and expect_end
  rejects extra input. (test/cli/std_json_exercise.iyi)
* json.7 Builder and Writer enforce one root, matched containers and object
  key/value alternation, refusing duplicate keys and unfinished or empty
  documents. raw inserts caller-owned JSON text verbatim without validating its
  grammar. (test/cli/std_json_exercise.iyi)
* json.8 Writers reject NaN and infinities and escape quotes, backslashes,
  controls and DEL. Invalid UTF-8 becomes U+FFFD per ill-formed subpart; ASCII-
  only output escapes non-ASCII scalars with surrogate pairs where needed.
  (test/cli/std_json_exercise.iyi)
* json.9 Pretty output uses the selected indentation string or positive space
  count; compact output adds no layout whitespace. JSON.write appends to a
  supplied builder and validates completion without clearing earlier text.
  (test/cli/std_json_exercise.iyi)
* json.10 to_json dispatches through ToJSON or scalar/container serialization;
  hash keys convert to text and colliding textual keys are refused. Typed
  from_json checks kinds and integer ranges, including exact UInt64 literals
  beyond Int64. (test/cli/std_json_exercise.iyi)
* json.11 Derived mappings and JSON::Field names support structured types; union
  decoding chooses by JSON kind and fitting integer representation, and nilable
  types accept null. (test/cli/std_json_exercise.iyi)
* json.12 Document nodes use a caller-tape RisTree view; unescaped keys and
  strings view the input, while escaped text views the document's decoded
  buffer. Any and RisJsonFields retain those roots, and text results use SPEC
  1.5; retention requires SPEC 1.7.
  <!-- todo: Needs proof -->

## kernel

Kernel supplies printing helpers and control utilities over the prelude.

* kernel.1 p and pp print inspect plus a newline for each argument and return
  the single argument or the argument tuple. pp currently uses the same
  representation as p. (test/cli/std_kernel_exercise.iyi)
* kernel.2 puts_all prints to_s and a newline for each argument; print_all
  prints to_s without adding separators or line endings.
  (test/cli/std_kernel_exercise.iyi)
* kernel.3 loop repeatedly yields until control leaves the block. No second
  sleep overload is supplied; the prelude's millisecond sleep remains in force.
  (test/cli/std_kernel_exercise.iyi)
* kernel.4 abort writes an optional message to STDERR with exactly one added
  newline when needed, then exits with the supplied status, default 1, using
  SPEC 4.1 cleanup. (test/cli/std_kernel_exercise.sh)

## levenshtein

Levenshtein computes character edit distances and finds close candidate names.

* levenshtein.1 distance counts insertions, deletions and substitutions at cost
  one per decoded character; equal inputs have distance zero. It uses byte
  comparisons for ASCII and decoded chars otherwise.
  (test/cli/std_levenshtein_exercise.iyi)
* levenshtein.2 osa_distance also counts an adjacent transposition as one edit,
  using optimal string alignment rather than unrestricted Damerau distance.
  (test/cli/std_levenshtein_exercise.iyi)
* levenshtein.3 Finder uses osa_distance, accepts candidates at or below
  tolerance, and retains the first candidate at the smallest distance. Without
  an explicit tolerance it uses (target.chars.size + 4) // 5; no accepted
  candidate yields nil. (test/cli/std_levenshtein_exercise.iyi)
* levenshtein.4 Finder borrows its target and candidate value strings;
  best_match returns that value without copying. Distance work arrays are
  scratch under SPEC 1.1.
  <!-- todo: Needs proof -->

## list

List is an immutable sequence with Enumerable operations and a pull iterator.

* list.1 Construction copies the input array's element slots; later mutation of
  that array does not change the list. Elements themselves are not deep-copied.
  (test/cli/std_exercise.iyi)
* list.2 Indexing counts negative indices from the end. [] and at panic outside
  the bounds, while []? returns nil; size and empty? describe the sequence.
  (test/cli/std_exercise.iyi)
* list.3 appended and concatenated return new sequences in original order
  followed by the new elements, leaving both inputs unchanged.
  (test/cli/std_exercise.iyi)
* list.4 Equality compares same-typed lists element by element in order; equal
  lists hash equally. Text and inspection use List[ followed by comma-separated
  inspected elements and ]. (test/cli/std_exercise.iyi)
* list.5 each visits elements in order; ListIterator consumes them in order,
  returning Stop after exhaustion. Adaptors over the same iterator share its
  progress. (test/cli/std_exercise.iyi)
* list.6 List storage uses the caller tape and retains its element roots; its
  immutability does not replace the sharing and lifetime checks of SPEC 3.2 and
  5.1.
  <!-- todo: Needs proof -->

## log

Log supplies severity filtering, hierarchical source names and structured
entries. Backends receive timestamped entries with context and per-call fields.

* log.1 Severity order is Trace, Debug, Info, Notice, Warn, Error, Fatal, None.
  Names parse case-insensitively; invalid parse? returns nil and parse panics.
  None suppresses all entries, including entries logged at None.
  (test/cli/std_log_exercise.iyi)
* log.2 Log.for caches the same logger for each exact dotted name, including
  empty segments. Children inherit level and backend dynamically until
  explicitly overridden; assigning nil restores inheritance. The default root
  level is Info. (test/cli/std_log_exercise.iyi)
* log.3 Entries below the effective threshold are discarded before evaluating a
  message block. Accepted entries contain source, severity, message, UTC
  timestamp and structured text fields. (test/cli/std_log_exercise.iyi)
* log.4 Field precedence is task context, bound logger fields, then call fields;
  later values replace earlier ones. with_context restores prior context on
  every exit and descendants started while it is open can inherit it.
  (test/cli/std_log_exercise.iyi)
* log.5 DefaultFormatter writes UTC timestamp text followed by LogText's
  severity, optional source, message and fields; IOBackend appends a newline and
  flushes synchronously. Closing IOBackend flushes without closing its supplied
  stream. (test/cli/std_log_exercise.iyi)
* log.6 RisMemoryBackend retains copied entries on its supplied Program tape,
  exposes recorded entries and formatted output and can clear them. Temporary
  TapeEntry data must be copied by a backend that retains it (SPEC 1.7).
  (test/cli/std_log_exercise.iyi)
* log.7 setup updates the root in place; setup_from_env reads the configured
  level variable, LOG_LEVEL by default, falling back to the supplied default
  when absent or unrecognized. (test/cli/std_log_exercise.iyi)
* log.8 AsyncBackend.open runs a descriptor writer in a scoped group and formats
  each entry before posting copied text. Only one instance may be open because
  all instances use the same board message type.
  <!-- todo: Needs proof -->
* log.9 AsyncBackend.close must wait until every earlier entry has reached the
  descriptor, be idempotent and reject subsequent writes; open must drain on
  scope exit.
  <!-- todo: close only posts a marker; joining waits until open exits. -->
  <!-- todo: Ignored failed board posts can lose entries or the end marker. -->
  <!-- todo: Needs proof -->

## log_text

LogText formats synchronous log text into a caller-supplied builder. It has no
clock or backend state.

* log_text.1 write appends a leading space, severity, " - ", an optional
  "source: ", and the message; it adds neither a timestamp nor a newline.
  <!-- todo: Needs proof -->
* log_text.2 Fields follow as " -- key=value" and then space-separated pairs.
  Empty values or values containing space, quote, equals or LF use
  String.inspect; other values are written verbatim.
  <!-- todo: Needs proof -->
* log_text.3 LogField.set replaces the first matching key in place or appends a
  new field. String text is borrowed, other values are printed into caller-tape
  text, and write appends directly to the supplied builder.
  <!-- todo: Needs proof -->

## mail

mail builds and parses Internet messages under RFC 5322 and MIME RFCs 2045,
2046, 2047 and 2231. It opens no network, clock or file resource.

* mail.1 Message construction requires From and Date and accepts To, Cc, Bcc,
  Reply-To, subject, optional Message-ID and extra headers. Bcc contributes
  envelope recipients but is omitted from wire headers; reserved headers cannot
  be replaced through extra fields. (test/cli/std_mail_exercise.iyi)
* mail.2 Text alone produces a text/plain part and HTML alone text/html;
  together they form multipart/alternative with plain first. Attachments wrap
  content in multipart/mixed and use base64; absent explicit types use MIME
  extension lookup. (test/cli/std_mail_exercise.iyi)
* mail.3 Text line endings become CRLF. Short ASCII lines use 7bit; other text
  chooses the shorter quoted-printable or base64 encoding. Boundaries derive
  deterministically from part hashes and are regenerated on a collision with
  content. (test/cli/std_mail_exercise.iyi)
* mail.4 Headers fold at whitespace toward 78 columns; indivisible long
  addresses may exceed that. Nonplain unstructured values and display names use
  UTF-8 RFC 2047 Q or B words of at most 75 characters without splitting a
  character; complex filenames use RFC 2231 parameters and continuations.
  (test/cli/std_mail_exercise.iyi)
* mail.5 Caller header names must be valid fields and header values and display
  names must not contain line breaks; invalid caller fields panic before being
  written. (test/cli/std_mail_exercise.iyi)
* mail.6 Address parsing accepts mailboxes, groups flattened to members, quoted
  local parts, domain literals, UTF-8, comments and obsolete routes. Comments
  are ignored rather than used as display names; malformed lists return
  MailError. (test/cli/std_mail_exercise.iyi)
* mail.7 date formats caller Unix seconds and a minute offset within -1439
  through 1439 for years 1900 through 9999. parse_date accepts RFC 5322 dates
  including obsolete years and zones, returning seconds and offset or MailError;
  it does not verify a supplied weekday against the date.
  (test/cli/std_mail_exercise.iyi)
* mail.8 Base64 encoding wraps at 76 characters; decoding ignores nonalphabet
  bytes and stops at padding. Quoted-printable uses soft line breaks and escapes
  trailing whitespace; malformed equals escapes are retained under RFC 2045's
  forgiving reader rules. (test/cli/std_mail_exercise.iyi)
* mail.9 The parser accepts CRLF or LF, unfolds fields in order and builds
  multipart and message/rfc822 child nodes. A malformed field, initial
  continuation, missing multipart boundary or terminator and nesting beyond 32
  return MailError. (test/cli/std_mail_exercise.iyi)
* mail.10 Header lookup is case-insensitive; decoded lookup reads encoded-words
  and leaves unrecognized words unchanged. Invalid Content-Type falls back to
  text/plain; parameter lookup handles extended and continued RFC 2231 values.
  (test/cli/std_mail_exercise.iyi)
* mail.11 body decodes the transfer encoding and returns MailError for
  unsupported encodings. text converts UTF-8, US-ASCII, ISO-8859-1, ISO-8859-15
  and windows-1252 to UTF-8 or reports invalid or unsupported charset data.
  (test/cli/std_mail_exercise.iyi)
* mail.12 Parts expose media type, filename, disposition and attachment
  predicates; walk traverses the part tree and find returns the first matching
  media type. attachments collects attachment parts without copying their
  bodies. (test/cli/std_mail_exercise.iyi)
* mail.13 TapePart views the RisMailParser's node and text storage and therefore
  cannot outlive it. Message setters borrow caller text; recipients and
  header_values write into caller containers and text builders. Encoded output
  and decoded text use SPEC 1.5.
  <!-- todo: Needs proof -->

## math

Math supplies numeric constants, elementary and special functions without a
platform libm dependency. Floating functions return numeric values, including
domain NaNs and signed infinities.

* math.1 PI, TAU, E, LOG2 and LOG10 are Float64 constants. Float32 overloads
  return Float32; generic numeric overloads convert to Float64 unless their
  signatures specify otherwise. (test/cli/std_math_exercise.iyi)
* math.2 sin, cos and tan take radians; inverse functions return radians, with
  atan2 using y then x and signed quadrants. Infinite trigonometric arguments
  and out-of-domain asin and acos produce NaN; signed zero is retained where the
  implemented function requires it. (test/cli/std_math_exercise.iyi)
* math.3 sqrt computes a nonnegative square root and returns NaN for negative
  nonzero input; cbrt returns the real cube root, including negative arguments
  and signed zero. (test/cli/std_math_exercise.iyi)
* math.4 exp, exp2 and expm1 compute e powers, two powers and e powers minus
  one; log, log2, log10 and log1p compute natural, base-two, base-ten and
  log(1+x). Zero logarithms produce negative infinity and negative-domain inputs
  produce NaN; two-argument log divides natural logarithms.
  (test/cli/std_math_exercise.iyi)
* math.5 pow implements floating exponentiation with explicit zero, sign, NaN
  and infinity cases; a finite negative base with a noninteger exponent yields
  NaN. Overflows and underflows yield infinities or zeros rather than integer-
  style panics. (test/cli/std_math_exercise.iyi)
* math.6 Hyperbolic and inverse hyperbolic functions use their real domains:
  acosh below one and atanh outside [-1,1] yield NaN, while atanh at the
  endpoints yields signed infinity. hypot scales its arguments to avoid
  avoidable square overflow. (test/cli/std_math_exercise.iyi)
* math.7 copysign copies the sign bit, including NaN and signed zero. fma
  computes a*b+c with one final rounding for Float32 and Float64, using hardware
  when available and software otherwise. (test/cli/std_math_exercise.iyi)
* math.8 min and max accept a pair representable by one argument type. Floating
  versions follow IEEE 754-2019 minimumNumber and maximumNumber, selecting the
  number beside one NaN and ordering -0.0 below +0.0; other types use < and
  return the first argument on a tie. (test/cli/std_math_exercise.iyi)
* math.9 frexp decomposes a finite nonzero value as a signed fraction of
  magnitude [0.5,1) and an exponent; zero and nonfinite values return unchanged
  with exponent zero. ldexp, scalbn and scalbln scale by powers of two,
  preserving special values and rounding subnormal results.
  (test/cli/std_math_exercise.iyi)
* math.10 ilogb returns the true binary exponent, Int32 minimum for zero and NaN
  and Int32 maximum for infinity. logb returns that exponent as a float,
  negative infinity for zero, positive infinity for infinity and NaN for NaN.
  (test/cli/std_math_exercise.iyi)
* math.11 erf and erfc compute the error function and its complement. gamma
  aliases tgamma: signed zero yields signed infinity, negative integers and
  negative infinity yield NaN. lgamma computes log absolute gamma and returns
  positive infinity at nonpositive integer poles and both infinities.
  (test/cli/std_math_exercise.iyi)
* math.12 Bessel J and Y are supplied for orders zero, one and signed integer
  orders; negative-order parity and the Y function's nonnegative real domain are
  enforced by the floating result branches. (test/cli/std_math_exercise.iyi)
* math.13 gcd and lcm require two integers of one type, return nonnegative
  results and panic on unrepresentable results. isqrt rejects negative integers
  and returns the greatest integer whose square does not exceed the input;
  pw2ceil returns one for inputs at most one and otherwise the least
  representable power of two at least the input, panicking on overflow.
  (test/cli/std_math_exercise.iyi)
* math.14 Functions return scalar values and retain no caller tape references;
  internal scratch follows SPEC 1.1. No caller cleanup is required.
  <!-- todo: Needs proof -->

## mime

MIME supplies a fixed extension table and media-type parsing and formatting. It
neither reads machine MIME tables nor sniffs file contents.

* mime.1 Extension lookup is ASCII case-insensitive and uses the last dot of the
  base name; a bare word may name an extension. Unknown names return nil or the
  supplied default, application/octet-stream by default.
  (test/cli/std_mime_exercise.iyi)
* mime.2 extensions ignores media-type parameters and case and returns dotted
  extensions in sorted order, as a fresh array; extensions_into uses caller-
  supplied result and text storage. (test/cli/std_mime_exercise.iyi)
* mime.3 parse? implements RFC 9110 section 8.3.1 tokens and quoted parameter
  values, undoing backslash escapes. It lowercases the type and parameter names,
  preserves value case and keeps the last repeated parameter; malformed input
  returns nil. (test/cli/std_mime_exercise.iyi)
* mime.4 compressible? recognizes text, structured JSON and XML types and the
  module's uncompressed binary formats; already compressed media and archives
  are false. (test/cli/std_mime_exercise.iyi)
* mime.5 with_charset adds charset=utf-8 to text, JSON, JavaScript and XML
  families only when no charset is present; malformed or other types are
  returned unchanged. Its builder overload appends to the caller.
  (test/cli/std_mime_exercise.iyi)
* mime.6 Parsed essence and parameters view normalized text built on the caller
  tape; unchanged text may still view input. Parameters support lookup,
  replacement and ordered traversal without owning an external resource.
  <!-- todo: Needs proof -->

## mlkem

mlkem implements ML-KEM-768 under FIPS 203. It uses caller-provided randomness
and performs no entropy or platform access itself.

* mlkem.1 from_seed requires 64 bytes, d followed by z, and deterministically
  produces the FIPS 203 key pair; a wrong seed length panics. Encapsulation
  randomness is exactly 32 bytes and a wrong length panics.
  (test/cli/std_mlkem_exercise.iyi)
* mlkem.2 Encapsulation keys are 1184 bytes, decapsulation keys 2400,
  ciphertexts 1088 and shared secrets 32. Encapsulation returns ciphertext and
  shared secret; decapsulation returns the same secret for a valid matching
  ciphertext. (test/cli/std_mlkem_exercise.iyi)
* mlkem.3 Encapsulation returns MlKemError for a wrong key length or a 12-bit
  public coefficient at least 3329. from_bytes checks decapsulation-key length
  and the embedded public-key hash under FIPS 203 section 7.
  (test/cli/std_mlkem_exercise.iyi)
* mlkem.4 A wrong ciphertext length returns MlKemError. Every correctly sized
  ciphertext produces a secret; failed reencryption comparison selects SHAKE256
  of z followed by the ciphertext as the implicit-rejection secret, without
  reporting validity. (test/cli/std_mlkem_exercise.iyi)
* mlkem.5 Secret-dependent arithmetic uses fixed loop bounds, masked reduction
  and selection; decapsulation compares every ciphertext byte before selecting
  all 32 secret bytes, without a secret-dependent early return.
  <!-- todo: Needs proof -->
* mlkem.6 Inputs are borrowed String or byte views and returned arrays use the
  caller destination (SPEC 1.5). Private keys retain their generated arrays;
  serialization produces byte arrays and no automatic secret wiping is supplied.
  <!-- todo: Needs proof -->

## named_tuple

Extends the prelude NamedTuple with dynamic lookup, merging and conversion.

* named_tuple.1 Construction from keyword arguments preserves the keys and their
  values. (test/cli/std_named_tuple_exercise.iyi)
* named_tuple.2 Symbol and String lookup use exact key names. Optional lookup
  returns nil for an absent key; fetch returns its default or calls its block
  with the missing key. Required dynamic lookup panics for a missing key.
  (test/cli/std_named_tuple_exercise.iyi)
* named_tuple.3 Key iteration follows declaration order; indexed iteration adds
  the supplied offset, zero by default. (test/cli/std_named_tuple_exercise.iyi)
* named_tuple.4 Merge keeps receiver entries not supplied by the other tuple,
  then the other entries in their order. The other values win; reverse_merge
  gives the receiver values precedence. (test/cli/std_named_tuple_exercise.iyi)
* named_tuple.5 Conversion to an Array returns ordered Symbol/value pairs,
  including heterogeneous values; an empty tuple gives an empty Array.
  Conversion to Hash writes into and returns the supplied Hash, overwriting
  matching keys. (test/cli/std_named_tuple_exercise.iyi)
* named_tuple.6 clone(owner) calls clone on values that provide it, keeps other
  values, then copies the resulting tuple to owner under SPEC 1.7. Conversion to
  Array retains its element references under SPEC 1.4.
  (test/cli/std_named_tuple_exercise.iyi)

## netip

Represents IP addresses, CIDR prefixes and prefix sets without sockets or name
resolution.

* netip.1 IPv4 parsing requires four decimal octets from 0 to 255, with no
  leading zeros. IPv6 parsing accepts RFC 4291 section 2.2 hex groups, one zero
  compression and a strict IPv4 tail, with at most 45 bytes before the zone. A
  slash is not address text; invalid text returns NetipError.
  (test/cli/std_netip_exercise.iyi)
* netip.2 IPv6 zones follow RFC 4007 section 11: a nonempty suffix after one
  percent sign. Parsed zones view input; with_zone borrows its argument. Empty
  with_zone removes the zone; a nonempty IPv4 zone or a zone containing percent
  panics. (test/cli/std_netip_exercise.iyi)
* netip.3 Integer and octet constructors use network byte order. Byte
  construction accepts exactly 4 or 16 bytes and otherwise panics; bytes returns
  a new Array of that length. (test/cli/std_netip_exercise.iyi)
* netip.4 IPv6 rendering follows RFC 5952 section 4: lowercase, no leading
  zeros, and the first longest run of at least two zero groups compressed.
  Mapped IPv4 tails stay dotted; exploded pads hex groups and retains zones. PTR
  names follow RFC 1035 section 3.5 or RFC 3596 section 2.5 and omit zones.
  (test/cli/std_netip_exercise.iyi)
* netip.5 Address equality includes family, bits and zone; order puts IPv4
  first, then bits, then zone. Mapped IPv6 remains distinct from IPv4; unmap and
  ipv4_mapped extract its IPv4 value, and ipv6_mapped refuses IPv6 input.
  Neighbours preserve zones and return nil at family bounds.
  (test/cli/std_netip_exercise.iyi)
* netip.6 Private means RFC 1918 IPv4 space or RFC 4193 fc00::/7. Loopback,
  unspecified, link-local, multicast, reserved and site-local use the encoded
  family ranges. Mapped addresses use their IPv4 classification except
  site-local. Global follows the module IANA special-purpose tables, with
  exceptions, and excludes 100.64.0.0/10. (test/cli/std_netip_exercise.iyi)
* netip.7 Prefix text accepts a decimal length, an IPv4 contiguous netmask or
  hostmask, or no suffix for full width. RFC 4632 host bits must be zero unless
  mask is true; zones and invalid text return NetipError. Construction preserves
  host bits but panics for zones or lengths outside the family width.
  (test/cli/std_netip_exercise.iyi)
* netip.8 Prefix block operations use the masked address: first, last, masks,
  containment and overlap. Families never cross; address containment ignores
  zones. Equality retains original host bits; order uses family, block start,
  length, then held address. (test/cli/std_netip_exercise.iyi)
* netip.9 Supernets cannot be longer than the prefix; subnets cannot be shorter
  or exceed family width. Invalid lengths or indices panic. subnets returns
  ordered blocks and refuses more than 65,536 at once; subnet reaches any valid
  UInt128 index. (test/cli/std_netip_exercise.iyi)
* netip.10 PrefixSet stores masked prefixes, deduplicates additions and reports
  whether add or delete changed membership. Exact membership differs from
  containment; lookup returns the longest containing prefix or nil, in at most
  33 IPv4 or 129 IPv6 steps. (test/cli/std_netip_exercise.iyi)
* netip.11 Prefix enumeration is in Prefix order, IPv4 first. collapsed returns
  the smallest exact cover by dropping covered descendants and merging full
  siblings. Enumeration and rendering results follow SPEC 1.5; classification
  and lookup build no collections. (test/cli/std_netip_exercise.iyi)

## number

Adds numeric identities, sign operations and named rounding modes.

* number.1 Concrete numeric types provide typed zero, additive identity and
  multiplicative identity. Unary plus returns the receiver; absolute value
  conditionally negates it and abs2 multiplies it by itself.
  (test/cli/std_number_exercise.iyi)
* number.2 Sign returns -1 for a negative value, 0 for zero and 1 otherwise.
  Zero, positive and negative predicates compare with zero.
  (test/cli/std_number_exercise.iyi)
* number.3 divmod returns the pair of the receiver divided with // and reduced
  with %; it inherits those operations, including their type-specific
  negative-operand rules. (test/cli/std_number_exercise.iyi)
* number.4 Integral rounding returns the receiver in every mode. Float64 modes
  round to nearest with ties to even or away from zero, toward zero, toward
  positive infinity or toward negative infinity.
  (test/cli/std_number_exercise.iyi)
* number.5 Float64 rounding preserves NaN, infinities, already integral
  magnitudes at least 2^53 and signed zero. Decimal-place rounding scales by
  powers of ten before rounding and scales back; negative places round to tens
  and larger powers. (test/cli/std_number_exercise.iyi)
* number.6 A decimal-place count of Int32::MIN must be handled without
  overflowing its negation.
  <!-- todo: Negating Int32::MIN overflows in number.iyi:120. -->

## number_format

Formats grouped numbers and quantities with SI or binary prefixes.

* number_format.1 format groups integer digits from the right, three per group
  by default, with configurable delimiter and decimal separator. Integers
  without places stay whole; floats without places expand their own shortest
  digits to decimal notation, keeping a fractional zero unless trimming is
  requested. (test/cli/std_number_format_exercise.iyi)
* number_format.2 Requested decimal places round the represented float exactly,
  with ties to even. Float32 uses its own shortest text without places and its
  widened exact value with places. only_significant removes trailing fractional
  zeros and an empty decimal separator.
  (test/cli/std_number_format_exercise.iyi)
* number_format.3 Grouped output that rounds to zero has no minus sign. NaN and
  infinities retain their numeric text.
  (test/cli/std_number_format_exercise.iyi)
* number_format.4 humanize uses SI prefixes q through Q in powers of 1000, three
  significant digits by default. Significant mode trims fractional zeros; place
  mode keeps requested places. Rounding may promote a prefix; values beyond the
  prefix range grow their digits, with integer groups of three.
  (test/cli/std_number_format_exercise.iyi)
* number_format.5 humanize_bytes takes integer byte counts and scales by 1024
  through EiB, or EB in JEDEC mode. Below 1024 it prints whole bytes. Precision,
  rounding promotion, decimal separator and unit separator are configurable.
  (test/cli/std_number_format_exercise.iyi)
* number_format.6 Invalid group sizes below one, negative places and
  insufficient precision panic; significant precision requires at least one
  digit and place precision at least zero. Finite fixed Float64 formatting
  permits at most 400 decimal places. (test/cli/std_number_format_exercise.iyi)
* number_format.7 Precision validation also applies to integer zero in humanize.
  <!-- todo: Integer zero skips validation in number_format.iyi:220. -->
* number_format.8 Each formatting operation either returns text under SPEC 1.5
  or appends to the supplied builder without replacing its prefix. Input text is
  borrowed. (src/std/number_format.iyi)

## ocsp

Reads and verifies OCSP responses and builds certificate status requests under
RFC 6960.

* ocsp.1 Parsing returns an OcspResponse or OcspError. Unsuccessful response
  statuses carry their numeric status; unused status 4, missing successful
  response bytes and non-basic response types are refused.
  (test/cli/std_ocsp_exercise.iyi)
* ocsp.2 A basic response exposes signed ResponseData, responder name or SHA-1
  key hash, producedAt, signature algorithm, signature, certificates and
  SingleResponses. Explicit default v1, malformed fields, non-GeneralizedTime
  times and empty response lists are refused; at most ten certificates may be
  carried. (test/cli/std_ocsp_exercise.iyi)
* ocsp.3 CertID accepts SHA-1, SHA-256, SHA-384 or SHA-512 with matching digest
  lengths and absent or NULL hash parameters. Matching compares leaf serial, the
  hash of its issuer name and the hash of the issuer public-key bits.
  (test/cli/std_ocsp_exercise.iyi)
* ocsp.4 SingleResponse distinguishes Good, Revoked and Unknown, preserving
  revocation time, optional RFC 5280 CRLReason, thisUpdate and optional
  nextUpdate. Invalid status encodings and reasons outside 0 through 10 or equal
  to 7 are refused. (test/cli/std_ocsp_exercise.iyi)
* ocsp.5 Extensions cannot repeat or be unknown and critical. The RFC 8954 nonce
  OCTET STRING is exposed but not matched to a request; unknown noncritical
  extensions are passed over. (test/cli/std_ocsp_exercise.iyi)
* ocsp.6 Verification first requires the leaf issuer name to equal the supplied
  issuer subject. It verifies a matching responder signature, then finds the
  first matching CertID and checks freshness. Signature policy is std/x509
  policy, including SHA-1 refusal. (test/cli/std_ocsp_exercise.iyi)
* ocsp.7 A delegated responder must be issued and signed by the issuer, valid at
  now, allowed id-kp-OCSPSigning and, when keyUsage is present,
  digitalSignature. Weak keys and unhandled critical extensions are refused. Its
  own revocation is not checked, with or without ocsp-nocheck.
  (test/cli/std_ocsp_exercise.iyi)
* ocsp.8 Freshness allows 300 seconds of skew by default. thisUpdate cannot
  exceed now plus skew; nextUpdate cannot precede thisUpdate or now minus skew.
  Without nextUpdate, validity ends 86,400 seconds after thisUpdate, with skew.
  Verification returns revoked and unknown as verdicts for the caller to judge.
  (test/cli/std_ocsp_exercise.iyi)
* ocsp.9 Requests contain one unsigned RFC 6960 CertID, defaulting to SHA-1,
  omit the default version and include a nonce extension only when supplied. No
  fetching, cache, CRL processing or intermediate revocation checking occurs.
  (test/cli/std_ocsp_exercise.iyi)
* ocsp.10 Parsed raw views borrow the DER Array. Retained response fields and
  certificates are copied into the caller RisOcspStore, and response and
  certificate lists view its appended ranges. Parsing does not clear the store;
  requests and digest results follow SPEC 1.5.
  <!-- todo: Needs proof; TODO.md:206 records retained OCSP data gaps. -->

## option_parser

Registers command-line flags and parses them into results read through flag
handles.

* option_parser.1 Registration returns an indexed RisFlag. A short and long
  spelling share a handle and the value requirement either spelling declares;
  conflicting required and optional declarations panic. Bare names and a lone
  dash cannot be registered. (test/ris/option_parser_panics.ri)
* option_parser.2 Required values accept separate arguments, long equals syntax
  and attached short syntax. Optional bracketed values consume a following
  argument unless it exactly names a registered flag; required values consume it
  even when it names a flag. Empty attached values are values.
  (test/ris/option_parser.ri)
* option_parser.3 Short names are one character, including UTF-8 characters.
  Bundles apply flags in order until a value-taking flag consumes the rest of
  the bundle. A bundle containing an unknown flag before that point applies none
  of it. (test/ris/option_parser.ri)
* option_parser.4 Parsing continues past operands and returns them in order. A
  double dash ends option processing and is omitted; subsequent arguments are
  operands. (test/ris/option_parser.ri)
* option_parser.5 Each parse clears previous results. Presence tests distinguish
  absent flags from flags with empty values; lookup returns the last supplied
  value or nil. Arguments are borrowed, and a previously read value remains a
  view of its original argument. (test/ris/option_parser.ri)
* option_parser.6 Unknown flags, values on valueless flags and missing required
  final values panic by default. record_errors instead records names in invalid
  or missing and continues. The returned arrays are the result storage,
  including any caller mutations. (test/ris/option_parser.ri)
* option_parser.7 Help writes the banner, defaulting to options:, then
  registered spellings, descriptions and separators in registration order with
  no final newline. The builder form appends; text results follow SPEC 1.5.
  Registration and banner strings are borrowed. (test/ris/option_parser.ri)
* option_parser.8 Registration and error callbacks are refused at compile time,
  naming flag handles or record_errors as their replacements. No command
  dispatch is performed. (test/ris/check.sh)
* option_parser.9 Lifetime refusals follow SPEC 3.6 at the caller parse call.
  <!-- todo: TODO.md:105 records a refusal inside the library instead. -->

## otp

Generates HOTP and TOTP codes and reads authenticator key URIs.

* otp.1 HOTP follows RFC 4226 section 5.3: HMAC of an eight-byte big-endian
  counter, dynamic truncation to 31 bits and a zero-padded decimal result. SHA-1
  is default; SHA-256 and SHA-512 are also supported. Secrets are byte Arrays.
  (test/cli/std_otp_exercise.iyi)
* otp.2 TOTP follows RFC 6238 with epoch T0 zero and counter unix_time // step,
  default step 30 seconds and six digits. now reads Time.utc; explicit-time
  operations use the supplied time. (test/cli/std_otp_exercise.iyi)
* otp.3 Verification compares every nonnegative counter within window steps of
  the current counter, one on either side by default, using constant-time code
  comparison. No accepted-counter state is retained: the caller prevents replay
  under RFC 6238 section 5.2. (test/cli/std_otp_exercise.iyi)
* otp.4 Empty secrets, digits outside 6 through 10, negative counters or times,
  nonpositive steps and negative windows panic. URI constructors also refuse
  empty accounts, colons in account or issuer and nonpositive periods.
  (test/cli/std_otp_exercise.sh)
* otp.5 OTPAuth writes Google Authenticator Key Uri Format: percent-encoded
  label components, uppercase unpadded base32 secret, optional issuer and HOTP
  counter, with algorithm, digits and TOTP period omitted at defaults SHA1, 6
  and 30. (test/cli/std_otp_exercise.iyi)
* otp.6 URI parsing accepts case-insensitive scheme, type and algorithm; decodes
  percent escapes, and plus as space in values; trims leading account spaces;
  and ignores unknown parameters. Recognized parameters cannot repeat. Label and
  parameter issuers must agree; HOTP requires a counter.
  (test/cli/std_otp_exercise.iyi)
* otp.7 Malformed URIs, bad escapes, absent or invalid secrets and out-of-range
  numeric fields return OTPError. TOTP ignores counter content and HOTP ignores
  period content. No QR image generation or delivery is provided.
  (test/cli/std_otp_exercise.iyi)
* otp.8 Constructed OTPAuth borrows account, issuer and secret storage. Parsing
  builds decoded account and issuer views and a new secret Array; serialized
  URIs and codes follow SPEC 1.5.
  <!-- todo: Needs proof -->

## p256

Makes deterministic ECDSA signatures and ECDH shared secrets on P-256.

* p256.1 Checked byte import accepts exactly 32 big-endian bytes representing d
  from 1 through n - 1, and otherwise returns EcdsaError. The public point is
  dG, uncompressed as 0x04 followed by two 32-byte coordinates.
  (test/cli/std_p256_exercise.iyi)
* p256.2 PKCS #8 import accepts RFC 5958 version 0 or 1, id-ecPublicKey and
  named curve prime256v1 (1.2.840.10045.3.1.7), containing an RFC 5915
  ECPrivateKey. SEC 1 import requires version 1 and the correct scalar length
  and range. (test/cli/std_p256_exercise.iyi)
* p256.3 An optional SEC 1 curve must name this curve, and an optional SEC 1
  public point must equal dG. Wrong algorithms, curves, points or malformed DER
  return EcdsaError. PKCS #8 trailing outer fields are not interpreted.
  (test/cli/std_p256_exercise.iyi)
* p256.4 Signing hashes the message with SHA-256, SHA-384 or SHA-512 and follows
  SEC 1 ECDSA with an RFC 6979 deterministic HMAC nonce. The same key, hash and
  message produce the same DER SEQUENCE of positive r and s INTEGERs. No random
  source is read. (test/cli/std_p256_exercise.iyi)
* p256.5 ECDH follows SEC 1 section 3.3.1 and returns the 32-byte big-endian x
  coordinate of dQ. The peer must have exactly 65 bytes, uncompressed tag 0x04,
  coordinates below p and a point on the curve; invalid points return EcdsaError
  before secret arithmetic. (test/cli/std_p256_exercise.iyi)
* p256.6 Secret scalar arithmetic uses fixed-width operations and masked table
  selection. Nonce rejection may repeat; DER encoding may branch on the public
  signature bytes. Parsing and public-key verification are outside this
  constant-time claim.
  <!-- todo: Needs proof -->
* p256.7 Key scalar bytes are decoded into value storage; derived public points,
  signatures and secrets use caller tape results under SPEC 1.5.
  copy_into_identity copies public-key storage and point bytes through the
  supplied identity store.
  <!-- todo: Needs proof -->
* p256.8 Direct constructors are lower-level forms: byte constructors decode
  without the checked import range validation; DER constructors may panic on
  malformed data. Callers needing error values use from_bytes, from_sec1 or
  from_pkcs8.
  <!-- todo: Needs proof -->

## p384

Makes deterministic ECDSA signatures and ECDH shared secrets on P-384.

* p384.1 Checked byte import accepts exactly 48 big-endian bytes representing d
  from 1 through n - 1, and otherwise returns EcdsaError. The public point is
  dG, uncompressed as 0x04 followed by two 48-byte coordinates.
  (test/cli/std_p384_exercise.iyi)
* p384.2 PKCS #8 import accepts RFC 5958 version 0 or 1, id-ecPublicKey and
  named curve secp384r1 (1.3.132.0.34), containing an RFC 5915 ECPrivateKey. SEC
  1 import requires version 1 and the correct scalar length and range.
  (test/cli/std_p384_exercise.iyi)
* p384.3 An optional SEC 1 curve must name this curve, and an optional SEC 1
  public point must equal dG. Wrong algorithms, curves, points or malformed DER
  return EcdsaError. PKCS #8 trailing outer fields are not interpreted.
  (test/cli/std_p384_exercise.iyi)
* p384.4 Signing hashes the message with SHA-256, SHA-384 or SHA-512 and follows
  SEC 1 ECDSA with an RFC 6979 deterministic HMAC nonce. The same key, hash and
  message produce the same DER SEQUENCE of positive r and s INTEGERs. No random
  source is read. (test/cli/std_p384_exercise.iyi)
* p384.5 sign_digest accepts only the named hash digest length, 32, 48 or 64
  bytes; other lengths return EcdsaError. SHA-512 is truncated to the leftmost
  384 bits; shorter digests are left-padded for scalar arithmetic.
  (test/cli/std_p384_exercise.iyi)
* p384.6 ECDH follows SEC 1 section 3.3.1 and returns the 48-byte big-endian x
  coordinate of dQ. The peer must have exactly 97 bytes, uncompressed tag 0x04,
  coordinates below p and a point on the curve; invalid points return EcdsaError
  before secret arithmetic. (test/cli/std_p384_exercise.iyi)
* p384.7 ECDH also refuses a product at infinity with EcdsaError.
  (test/cli/std_p384_exercise.sh)
* p384.8 Secret scalar arithmetic uses fixed-width operations and masked table
  selection. Nonce rejection may repeat; DER encoding may branch on the public
  signature bytes. Parsing and public-key verification are outside this
  constant-time claim.
  <!-- todo: Needs proof -->
* p384.9 Key scalar bytes are decoded into value storage; derived public points,
  signatures and secrets use caller tape results under SPEC 1.5.
  copy_into_identity copies public-key storage and point bytes through the
  supplied identity store.
  <!-- todo: Needs proof -->
* p384.10 Direct constructors are lower-level forms: byte constructors decode
  without the checked import range validation; DER constructors may panic on
  malformed data. Callers needing error values use from_bytes, from_sec1 or
  from_pkcs8.
  <!-- todo: Needs proof -->

## password

Hashes passwords with bcrypt and derives raw keys with scrypt.

* password.1 Scrypt follows RFC 7914 using PBKDF2-HMAC-SHA256, ROMix and
  Salsa20/8. String inputs supply their bytes; byte Arrays are also accepted.
  The result is a new Array of the requested positive byte length.
  (test/cli/std_password_exercise.iyi)
* password.2 Scrypt requires n to be a power of two above one and below 2^(16r),
  positive r and p, and 128*r*p to fit Int32. It panics before working when
  128*r*p + 128*r*(n+2) exceeds max_memory, default 33,554,432 bytes.
  (test/cli/std_password_exercise.sh)
* password.3 Bcrypt writes the OpenBSD 60-character $2b$ form with cost and
  bcrypt-base64 salt and hash. It draws a fresh 16-byte secure salt. Cost
  defaults to 11 and must be 4 through 31, otherwise hash panics.
  (test/cli/std_password_exercise.iyi)
* password.4 Bcrypt uses password bytes before the first NUL, at most 72 bytes,
  with a terminating NUL only when room remains. Bytes after that limit do not
  affect verification. (test/cli/std_password_exercise.iyi)
* password.5 Verification accepts $2a$, $2b$ and $2y$ as the current key
  schedule; old $2a$ length-wrap behavior is not reproduced. Wrong passwords,
  malformed stored hashes and invalid costs return false. Candidate comparison
  is constant-time after parsing and hashing.
  (test/cli/std_password_exercise.iyi)
* password.6 Password and salt inputs are borrowed; derived bytes and hash text
  follow SPEC 1.5. Bcrypt may copy up to 72 String bytes as working storage;
  neither API requires closing a resource.
  <!-- todo: Needs proof -->

## path

Manipulates POSIX and Windows path names lexically, with optional environment-
based expansion.

* path.1 A Path keeps its name and kind; construction borrows the name without
  normalizing. Native kind follows the target, with explicit posix and windows
  constructors. POSIX separates on slash; Windows accepts slash and backslash.
  (test/cli/std_path_exercise.iyi)
* path.2 Drive, root and anchor are slices of the name or nil. POSIX rooted
  paths are absolute. Windows drive-and-root and UNC share paths are absolute;
  drive-relative and bare-root paths are relative. Long UNC names include the
  server and share in the drive. (test/cli/std_path_exercise.iyi)
* path.3 Basename ignores trailing separators and removes a matching suffix only
  when it is shorter than the basename. Dirname gives dot for a bare or empty
  name. Extension excludes leading-only and trailing dots, and anchors have no
  extension; stem removes the extension. (test/cli/std_path_exercise.iyi)
* path.4 Parts yield the anchor then nonempty components. Parent keeps the path
  kind and spelling; parents and each_parent enumerate ancestors from outermost
  to nearest, without including the path itself.
  (test/cli/std_path_exercise.iyi)
* path.5 Joining keeps the receiver kind and treats the other name with that
  syntax. An anchored right side replaces the left except a Windows root retains
  its drive and a same-drive relative right side appends. Empty parts do not add
  separators; sibling joins under parent. (test/cli/std_path_exercise.iyi)
* path.6 Normalization collapses separators, drops dot components and cancels
  preceding components for dot-dot. Relative leading dot-dot remains; rooted
  paths cannot climb above root. Empty relative results are dot, and Windows
  output uses backslash separators. (test/cli/std_path_exercise.iyi)
* path.7 Relative paths compare normalized anchors and components. Different
  anchors or unmatched dot-dot components in the base return nil from
  relative_to? and panic from relative_to; identical paths give dot.
  (test/cli/std_path_exercise.iyi)
* path.8 expand normalizes an absolute path or joins a relative path under an
  absolute base. Without a base it uses PWD then Program.cwd on POSIX, or
  Program.cwd on Windows. Missing or relative bases panic. home expands only a
  leading tilde component, from HOME or Windows USERPROFILE then HOME.
  (test/cli/std_path_exercise.iyi)
* path.9 Windows comparison folds separators and ASCII case, and on Windows also
  uses native nonlinguistic case folding. POSIX comparison is bytewise; kind
  distinguishes equal names. Hash uses the same per-kind folding. No implicit
  normalization occurs during equality. (test/cli/std_path_exercise.iyi)
* path.10 to_posix changes backslashes to slashes when converting Windows names;
  to_windows changes kind without rewriting the name. Text writing appends the
  held name. Name slices borrow input; transformed names and result Arrays
  follow SPEC 1.5. (test/cli/std_path_exercise.iyi)

## png

Reads and writes PNG images under ISO/IEC 15948:2004 and the W3C PNG
specification, with the coverage below.

* png.1 Decoding accepts all standard color-type and bit-depth pairs, with or
  without Adam7, and all five filters. Sub-byte gray is scaled to eight bits by
  bit replication; palette indices expand to RGB or RGBA. Sixteen-bit samples
  remain big-endian sixteen-bit samples. (test/cli/std_png_exercise.iyi)
* png.2 Images expose positive width and height, Gray, GrayAlpha, RGB or RGBA
  layout and row-major samples at depth 8 or 16. Manual construction panics for
  wrong sample counts or invalid transparent-color shape or range. Sample lookup
  panics for coordinates or channels out of bounds.
  (test/cli/std_png_exercise.iyi)
* png.3 to_rgba8 replicates gray, uses stored alpha or opaque 255, and gives an
  exact transparent-color match alpha zero. Sixteen-bit output uses each sample
  high byte while transparent-color comparison uses the full sample.
  (test/cli/std_png_exercise.iyi)
* png.4 The decoder checks the eight-byte signature, chunk bounds, four
  ASCII-letter names, CRC-32 and recognized critical chunks. IHDR must be first
  and unique, PLTE must precede IDAT, IDAT chunks must be consecutive, and IEND
  must occur after image data. Invalid files return PngError.
  (test/cli/std_png_exercise.iyi)
* png.5 IEND must have zero content bytes, as required by ISO/IEC 15948.
  <!-- todo: png.iyi:1066 accepts IEND without checking its length. -->
* png.6 IHDR accepts dimensions 1 through 2^31 - 1, compression and filter
  methods zero and interlace 0 or 1. Pixel counts above max_pixels, default
  89,478,485, are refused before allocating pixels; raw or expanded data beyond
  Int32 string capacity is refused. (test/cli/std_png_exercise.iyi)
* png.7 The zlib image stream must inflate to exactly the expected pass and row
  size; excess is refused after at most one 64 KiB read beyond that size.
  Corrupt streams, invalid filter bytes and out-of-range palette indices return
  PngError. Compressed metadata is limited to 8 MiB per chunk.
  (test/cli/std_png_exercise.iyi)
* png.8 PLTE has 1 through 256 RGB entries and cannot exceed the index depth.
  tRNS must precede IDAT and fit its color type; it cannot accompany an alpha
  channel. Missing palette alpha is 255; gray or RGB transparent colors are
  retained when representable. (test/cli/std_png_exercise.iyi)
* png.9 gAMA, sRGB, iCCP and tEXt, zTXt, iTXt are exposed; compressed profiles
  and texts are inflated. Latin-1 text becomes UTF-8. Unknown ancillary chunks,
  including animation, cHRM and cICP, are skipped and their names retained in
  order; color management is not applied. (test/cli/std_png_exercise.iyi)
* png.10 The decoder exposes cHRM and cICP metadata as well as
  gAMA, sRGB and iCCP.
  <!-- todo: Header claims cHRM/cICP; png.iyi:1116 skips them. -->
* png.11 Encoding writes Gray, GrayAlpha, RGB and RGBA at 8 or 16 bits, optional
  tRNS and optional Adam7. It tries all row filters and chooses the first with
  the least sum of absolute signed bytes, as section 12.8 recommends; IDAT
  content is split at 65,536 bytes. (test/cli/std_png_exercise.iyi)
* png.12 Indexed encoding accepts one byte per pixel and 1 through 256 RGBA
  palette entries; invalid dimensions, lengths, indices or samples panic. It
  chooses the smallest depth of 1, 2, 4 or 8 that holds the palette, uses filter
  zero and omits trailing opaque tRNS entries. (test/cli/std_png_exercise.iyi)
* png.13 Text encoding uses tEXt for Latin-1 text and iTXt otherwise. Keywords
  must be 1 through 79 printable Latin-1 bytes with no edge or repeated spaces;
  text cannot contain NUL. Invalid text inputs panic. No animation,
  color-profile writing or sub-byte grayscale encoding is provided.
  (test/cli/std_png_exercise.iyi)
* png.14 Decode borrows input for palette, transparency, skipped names and some
  iTXt fields; pixels and decoded metadata are newly built. Manual Image
  construction borrows sample and transparency storage. Encoded files and
  converted pixel text follow SPEC 1.5; no resource needs closing.
  <!-- todo: Needs proof -->

## process

Starts child programs and provides fiber-aware input, output and process
completion.

* process.1 Commands receive each argument as one argv element, without shell
  expansion. Bare names are searched on the parent PATH, and path names are
  resolved before applying child chdir. Empty commands, NUL bytes in command,
  arguments or directory, and invalid environment names or NUL values panic.
  (test/cli/std_process_exercise.iyi)
* process.2 run waits for completion and returns ProcessResult even for nonzero
  exits. By default it writes supplied input, or supplies the null device, and
  captures stdout and stderr separately while draining both. capture false
  inherits streams and returns empty captured texts.
  (test/cli/std_process_exercise.iyi)
* process.3 A program that cannot start returns ProcessError carrying command,
  platform error code and, for a working-directory error, directory. not_found?,
  denied?, reason and message distinguish common launch failures.
  (test/cli/std_process_exercise.iyi)
* process.4 Environment changes apply to the child alone: values set names and
  nil removes them. A chdir removes inherited PWD unless env explicitly supplies
  it. Windows names are case-insensitive. This does not change the parent PATH
  used for command lookup. (test/cli/std_process_exercise.iyi)
* process.5 spawn returns ChildProcess or ProcessError without waiting for the
  child to finish. Each stream independently selects Pipe, Inherit or Null,
  default Inherit. Access to a stream not requested as Pipe panics; inherited
  buffered output is flushed before launch. (test/cli/std_process_exercise.iyi)
* process.6 Input write sends the whole String while parking on a full pipe, or
  returns ChildInputClosed when the child or caller closed input. Closing input
  supplies EOF. Output read takes at most a positive maximum and returns nil at
  EOF; nonpositive maxima panic. (test/cli/std_process_exercise.iyi)
* process.7 read_line returns a line, optionally stripping LF and its preceding
  CR, or the final unterminated text before nil. read_all returns all remaining
  bytes. Output handle copies share cursor and buffered storage; returned
  buffered lines view stable storage. read_both drains both piped outputs
  concurrently, returning texts or appending to supplied builders.
  (test/cli/std_process_exercise.iyi)
* process.8 Every spawned child must be waited for. wait closes input first,
  parks until completion and returns cached ProcessStatus on repeated calls.
  ended? polls completion; status is nil until completion has been observed.
  Successful status means signal zero and exit code zero.
  (test/cli/std_process_exercise.iyi)
* process.9 Cancellation encountered in run, waiting or stream IO kills and
  reaps the child and closes its pipes before returning Cancelled, under SPEC
  5.1 and 5.6. Ordinary run and IO park fibers so other tasks can progress.
  (test/cli/std_process_exercise.iyi)
* process.10 On POSIX, signal sends a number from 1 through 64, terminate sends
  SIGTERM and kill sends SIGKILL; completed children are left alone. Signal
  termination reports the signal and exit code 128 plus that signal. Windows has
  no signal operation and panics on it. (test/cli/std_process_exercise.iyi)
* process.11 exec replaces the POSIX program with the same pid and standard
  streams, returning ProcessError only on failure; it restores chdir on a failed
  replacement. Windows instead runs the child, waits and exits with its code.
  Buffered standard output and error are flushed first.
  (test/cli/std_process_exercise.sh)
* process.12 pid identifies this process and executable returns its path or nil
  when unavailable. Resource handles and captured text reside on their caller
  tape under SPEC 1.5; ending tape storage does not replace the caller
  obligation to wait and finish pipe use. (test/cli/std_process_exercise.iyi)
* process.13 Target availability follows SPEC 7.1. The inherited Windows
  implementation searches .exe and .com for bare extensionless names, refuses
  .bat and .cmd, and requires UTF-8 convertible to its native command line;
  Windows exit signal is zero and exception exit codes are read as Int32.
  (test/cli/std_process_exercise.iyi)

## query

Reads ordered query parameters and writes form-encoded query text.

* query.1 Parsing drops one leading question mark, splits on ampersand or
  semicolon and ignores empty parts. The first equals sign separates key and
  value; an absent equals gives an empty value. Empty keys, duplicate keys and
  original pair order are retained. (src/std/query.iyi)
* query.2 Decoding maps plus to space and valid percent escapes to bytes. A
  percent sign without two hex digits is literal; malformed escapes do not
  return an error. This extends WHATWG form query parsing by also accepting
  semicolon separators. (src/std/query.iyi)
* query.3 size counts pairs, each yields names and values in order and optional
  key lookup returns the first matching value or nil. (src/std/query.iyi)
* query.4 Serialization appends each encoded key, equals and value to the
  supplied builder, with ampersands between pairs. Form encoding preserves ASCII
  letters, digits, asterisk, dash, dot and underscore, writes space as plus and
  other bytes as uppercase percent escapes.
  <!-- todo: Needs proof -->
* query.5 Parsing copies decoded components into the Query builder on the caller
  tape; pairs view that storage. Empty values without equals may view the input
  empty slice. QueryPair construction borrows its strings; retention follows
  SPEC 1.7.
  <!-- todo: Needs proof -->

## random

Provides deterministic PCG-32 draws, operating-system entropy and collection
sampling.

* random.1 A seeded Random uses PCG-32 with the supplied initial state and
  sequence, default sequence zero. Same seeds and call order reproduce the same
  draws; integer seeds and sequences are converted to UInt64 and negative ones
  panic. Unseeded construction obtains entropy from the secure source.
  (test/cli/std_random_exercise.iyi)
* random.2 next_u returns 32 random bits and next_bool its low bit. next_float
  and argumentless rand combine two draws, high first, to give 53-bit fractions
  including both zero and one. PCG is not a cryptographic generator.
  (test/cli/std_random_exercise.iyi)
* random.3 Positive integer bounds give unbiased draws in 0...n using rejection,
  one raw draw through a 2^32 span and two for wider spans. Integer ranges honor
  exclusive ends and support the entire Int32 and Int64 domains. Empty bounds or
  ranges panic. (test/cli/std_random_exercise.iyi)
* random.4 A positive floating bound scales a 53-bit fraction with denominator
  2^53. Exclusive floating ranges use that bounded draw; inclusive ones scale
  argumentless rand and may reach either endpoint. Nonpositive or NaN bounds and
  reversed ranges panic. (test/cli/std_random_exercise.iyi)
* random.5 random_bytes fills a supplied Array or returns a new one, default 16
  bytes; negative counts panic. Seeded draws emit four bytes per word, low byte
  first. hex writes lowercase pairs; base64 is padded and has no line breaks;
  URL-safe base64 omits padding unless requested.
  (test/cli/std_random_exercise.iyi)
* random.6 Class methods use one lazily initialized PCG generator retained on
  Program.tape. Secure class methods instead use the operating system for each
  draw; secure byte fills use the whole supplied buffer and keep no random-byte
  cache. (test/cli/std_random_exercise.iyi)
* random.7 On Linux, secure filling retries interrupted and short getrandom
  calls, falling back only for ENOSYS to /dev/urandom after verifying a
  character device. Failures panic. Darwin uses arc4random_buf. Other target
  availability follows SPEC 7.1. (test/cli/std_random_exercise.sh)
* random.8 Array and StaticArray in-place shuffle use backward Fisher-Yates;
  Array shuffle returns a shallow copy. A supplied generator controls draws,
  otherwise a fresh one is created. Single sampling of an empty Array panics;
  sample(n) refuses negative n and returns at most size distinct positions, with
  a shuffled reservoir for larger samples. (test/cli/std_random_exercise.iyi)
* random.9 New byte Arrays, encoded text and sampled or shuffled Arrays follow
  SPEC 1.5. Collection copies retain element references under SPEC 1.4;
  caller-supplied buffers are overwritten in place. No resource needs closing.
  <!-- todo: Needs proof -->

## reference_storage

Provides low-level manual storage for reference instances and construction at a
supplied address.

* reference_storage.1 ReferenceStorage(T) requires a non-union reference type
  and has its instance size and alignment. Invalid type arguments are
  compile-time errors. (test/cli/std_reference_storage_exercise.sh)
* reference_storage.2 pre_initialize writes the runtime type information at a
  caller-supplied address and returns that reference. unsafe_construct
  additionally invokes initialize with the supplied arguments. The caller
  supplies valid aligned storage and keeps it alive; to_reference aliases that
  storage without allocation. (test/cli/std_reference_storage_exercise.iyi)
* reference_storage.3 Equality compares instance fields, using identity for
  class-typed fields and each other field own equality. Padding is ignored and
  other object types compare false. Hash applies the same field distinctions, so
  equal storages hash alike. (test/cli/std_reference_storage_exercise.iyi)
* reference_storage.4 String and inspection output is ReferenceStorage(#<T>),
  using the fully qualified type name; produced text follows SPEC 1.5. This API
  does not own, free or close the referenced storage.
  (test/cli/std_reference_storage_exercise.iyi)

## regex

Compiles and matches regular expressions with RE2-style leftmost-first behavior.

* regex.1 Alternation chooses the first matching alternative at the leftmost
  start. Greedy repetition prefers longer consumption and lazy repetition
  shorter consumption. Searches use finite-state matching without backtracking;
  work for a fixed compiled pattern is bounded by text length and its machine
  and capture sizes. (test/cli/std_regex_exercise.iyi)
* regex.2 The grammar supports character and negated classes, alternation,
  captures, named and noncapturing groups, anchors, word boundaries, greedy and
  lazy counts, ASCII shorthand and POSIX classes, Unicode categories and
  scripts, hex and octal escapes and quoted literal runs. Lookaround,
  backreferences, recursion, atomic groups and possessive quantifiers panic with
  a reason. (test/cli/std_regex_exercise.iyi)
* regex.3 Count limits are 1000, including the product of nested counts; group
  nesting is limited to 100. Reversed ranges, unmatched delimiters, unknown
  escapes or flags and malformed group forms panic during compilation. A brace
  that does not form a count is literal. (test/cli/std_regex_exercise.sh)
* regex.4 Matching reads UTF-8 code points; an invalid leading byte is one
  replacement character consuming one byte. Shorthand word, digit and whitespace
  classes and word boundaries use ASCII definitions. Ignore-case uses Unicode
  simple folding, and Unicode property names use std/unicode tables.
  (test/cli/std_regex_exercise.iyi)
* regex.5 Inline i, m, s, U and x flags may be set, unset or scoped.
  Whole-pattern options provide case folding, extended syntax, DOTALL and
  MULTILINE_ONLY; MULTILINE combines dot-all and line anchors. Extended syntax
  ignores whitespace and comments outside classes.
  (test/cli/std_regex_exercise.iyi)
* regex.6 match? requires a whole-text match; find, === and String matches?
  search anywhere. match returns groups from the first match at or after a byte
  offset; match_at requires that exact byte offset. Negative offsets count from
  the byte end and out-of-range offsets return nil. Anchors still refer to the
  original text. (test/cli/std_regex_exercise.iyi)
* regex.7 MatchData borrows the matched text. Group zero is the whole match;
  numbered and named optional access returns nil for missing or unmatched
  groups, required access and offsets panic. Negative numbers count from the
  last group. Byte offsets and character offsets are exposed separately.
  (test/cli/std_regex_exercise.iyi)
* regex.8 Capture arrays omit named groups; to_a includes all groups including
  zero; named_captures and name_table write to caller Hashes. pre_match and
  post_match are input views. Group counts, names and indices describe the
  compiled pattern. (test/cli/std_regex_exercise.iyi)
* regex.9 scan and each_match enumerate nonoverlapping matches. After an empty
  match, another empty match at that position is forbidden while a nonempty one
  may still consume there. split includes the final remainder and empty boundary
  pieces without inserting capture groups. (test/cli/std_regex_exercise.iyi)
* regex.10 Regex replace substitutes every match with literal replacement text
  or its block result. String sub replaces the first and gsub every match; their
  String replacements expand backslash digits 0 through 9 and named references,
  treating unmatched groups as empty. Invalid named references panic; table gsub
  drops matches absent from the table. (test/cli/std_regex_exercise.iyi)
* regex.11 escape quotes metacharacters, including extended-mode whitespace and
  hash. union escapes String alternatives and preserves Regex flags in scoped
  alternatives. source preserves original text, options reports external flags
  only, and equality compares both. (test/cli/std_regex_exercise.iyi)
* regex.12 Compiled storage and capture-position Arrays use the caller tape;
  matched Strings remain views of input. New replacement and escaped text follow
  SPEC 1.5, and no-match String sub may return the original view. No implicit
  last-match global is set.
  <!-- todo: Needs proof -->

## ris_spec

This is internal test support imported by spec-enabled builds for temporary
files and program runs.

* ris_spec.1 RisTmp creates a process-id and counter-based temporary directory.
  file creates parent directories, read returns file contents and children
  returns sorted names. close removes registered background processes and then
  recursively removes the directory. (test/cli/spec_blocks_program.sh)
* ris_spec.2 RisProgram requires RIS_SPEC_PROGRAM or panics with instructions to
  use ris test. run starts that binary in the temporary directory with supplied
  arguments and input and returns stdout, stderr and exit status. RisRun
  comparison with String compares stdout; regex matching searches stdout.
  (test/cli/spec_blocks_program.sh)
* ris_spec.3 Child environments inherit the parent, remove RIS_SPEC_JSON and
  RIS_SPEC_PROGRAM, set HOME and TMPDIR to the block directory and then apply
  supplied overrides. (test/cli/spec_blocks_program.sh)
* ris_spec.4 Background runs redirect stdout and stderr to files beside the
  temporary directory through /bin/sh. stdout and stderr read their current
  contents, or empty when absent. write feeds stdin; status is nil until
  completion has been observed and then gives the exit code.
  (test/cli/spec_blocks_program.sh)
* ris_spec.5 wait_for checks stdout for a regex every 20 milliseconds until
  matched, process completion or timeout, default ten seconds. stop sends TERM,
  waits up to two seconds, then kills if needed and caches the final status.
  remove stops the child and deletes its logs. (test/cli/spec_blocks_program.sh)
* ris_spec.6 A background process must be registered with its RisTmp for block
  cleanup; callers using start directly register it themselves. Run output and
  inspection text follow SPEC 1.5. These helpers are absent from ordinary
  spec-free builds. (test/cli/spec_blocks_program.sh)
* ris_spec.7 free_port binds a temporary TCP listener on 127.0.0.1 port zero,
  returns the assigned port and closes the listener. The returned number does
  not reserve that port.
  <!-- todo: Needs proof -->

## router

Routes std/http requests using Go ServeMux patterns and path cleaning.

* router.1 Patterns have optional method and host before a rooted path. Method
  comparison is exact, except GET also matches HEAD; an omitted method matches
  every method. Host matching is exact after the request Host port is dropped.
  (test/cli/std_router_exercise.iyi)
* router.2 Paths match percent-decoded segments. A named wildcard matches one
  nonempty segment; a final rest wildcard matches remaining segments, including
  an empty tail after a slash. A trailing slash is an unnamed rest wildcard; {$}
  matches the path end only. Escaped slashes stay inside a segment.
  (test/cli/std_router_exercise.iyi)
* router.3 Parsing returns Pattern or RouterError. It refuses invalid methods,
  missing paths, host braces, unclean paths, bad percent escapes,
  partial-segment wildcards, nonfinal rest or end wildcards, duplicate names and
  names outside ASCII identifiers. (test/cli/std_router_exercise.iyi)
  <!-- todo: TODO.md:32 records Pattern.parse failing SPEC 1.9. -->
* router.4 Pattern relation compares method and path request sets as equivalent,
  more general, more specific, disjoint or overlapping. Same-host patterns with
  equivalent or overlapping sets conflict; registering the second panics with
  both names and, for overlap, a shared request.
  (test/cli/std_router_exercise.iyi)
* router.5 Among matching routes, host-specific patterns beat hostless ones;
  otherwise the strict subset of requests wins. Registration order does not
  decide precedence. Registration after the first call panics; patterns returns
  a shallow Array copy in registration order. (test/cli/std_router_exercise.iyi)
* router.6 The selected handler receives request, response and a Hash of decoded
  wildcard names and values. Captures supports ordered entries, addition,
  first-name lookup with panic on absence and conversion to Hash. Pattern match
  compares paths only and returns nil on failure.
  (test/cli/std_router_exercise.iyi)
* router.7 Raw dot and dot-dot segments and repeated slashes are cleaned before
  matching, with a trailing slash retained. Changed paths redirect with 307 and
  the query retained; escaped dots and slashes are not cleaned as path syntax.
  (test/cli/std_router_exercise.iyi)
* router.8 A missing slash redirects with 307 when adding it reaches an exact
  subtree root and the original path has no exact match. Redirects preserve
  query text. The policy follows Go 1.26, differing from Go 1.22 through 1.25
  permanent redirects. (test/cli/std_router_exercise.iyi)
* router.9 A matching path, including a potential trailing-slash match, under
  other methods returns 405 with sorted Allow and HEAD added for GET. Other
  misses return 404; malformed path escapes give 400 and nonpath targets give
  404. Plain error bodies use text/plain; charset=utf-8.
  (test/cli/std_router_exercise.iyi)
* router.10 Pattern text, methods, hosts and names may borrow registration text;
  decoded literals and capture values use tape storage. Request capture Hashes
  and clean text follow SPEC 1.5; handler retention follows SPEC 5.3.
  <!-- todo: Needs proof; TODO.md:202 records escaping router callbacks. -->

## rsa

Reads RSA keys and checks or makes PKCS #1 v1.5 and PSS signatures under RFC
8017.

* rsa.1 Checked public-key construction reads unsigned big-endian modulus and
  exponent. It requires an odd modulus from 1024 through 16384 bits and an odd
  exponent from 3 through 2^31 - 1; invalid keys return RsaError.
  (test/cli/std_rsa_exercise.iyi)
* rsa.2 Public import accepts DER RSAPublicKey or SubjectPublicKeyInfo with
  rsaEncryption and NULL parameters under RFC 3279 section 2.3.1. Exposed size
  is ceil(bits/8). Malformed DER, wrong algorithms or parameters return
  RsaError. (test/cli/std_rsa_exercise.iyi)
* rsa.3 PKCS #1 v1.5 verification compares the complete RFC 8017 EMSA encoding,
  including every padding byte, NULL-parameter DigestInfo and digest. It
  verifies SHA-1, SHA-256, SHA-384 and SHA-512 without accepting alternate BER
  encodings. (test/cli/std_rsa_exercise.iyi)
* rsa.4 PSS verification uses emBits = modulus bits minus one, MGF1 under the
  same hash, trailer 0xbc, the exact padding and the specified salt length,
  default digest length. Wrong-length signatures, values at least the modulus
  and any encoding or digest failure return false.
  (test/cli/std_rsa_exercise.iyi)
* rsa.5 Private import accepts two-prime version-zero PKCS #1 and version-zero
  or version-one PKCS #8 rsaEncryption with NULL parameters. PEM must contain
  exactly one RSA PRIVATE KEY or PRIVATE KEY block. Encrypted, multi-prime and
  restricted RSASSA-PSS keys return RsaError. (test/cli/std_rsa_exercise.iyi)
* rsa.6 Private keys require at least 2048 modulus bits, p and q greater than
  one with product n, e*d congruent to one modulo lcm(p-1,q-1), correct dp and
  dq and qi below p with qi*q congruent to one modulo p. Version-one PKCS #8
  carried public keys must agree; attributes are ignored.
  (test/cli/std_rsa_exercise.iyi)
* rsa.7 Signing accepts SHA-256, SHA-384 and SHA-512; SHA-1 panics. PKCS #1 v1.5
  signs its canonical encoding; PSS uses a digest-length HMAC-derived salt keyed
  from the private exponent, making repeated signing deterministic without
  platform entropy. (test/cli/std_rsa_exercise.iyi)
* rsa.8 Private operations blind the encoded message, exponentiate by CRT with
  secret-exponent routines, remove blinding and verify the signature with the
  public exponent before returning it. A CRT fault or oversized signature panics
  rather than releasing an invalid signature. (test/cli/std_rsa_exercise.sh)
* rsa.9 Digest helpers return bytes of the named hash and its canonical
  DigestInfo prefix. Key numbers are decoded into new BigInt storage; signatures
  and imported keys follow SPEC 1.5, with explicit copies where required.
  copy_into_identity copies numbers and PRF bytes through the caller store.
  <!-- todo: Needs proof -->
* rsa.10 Direct BigInt and DER constructors are lower-level forms and may panic
  or trust prevalidated fields. The checked new and from_* entry points supply
  the error-value validation above. No RSA encryption, decryption or key
  generation is provided.
  <!-- todo: Needs proof -->

## secure_dns

Provides encrypted DNS upstreams using DNS over TLS and DNS over HTTPS.

* secure_dns.1 DNS over TLS follows RFC 7858 framing with two-byte message
  lengths, default port 853. Construction requires a valid authentication name,
  numeric IPv4 or IPv6 address, port 1 through 65535 and nonnegative idle
  timeout; misuse panics. TLS checks the configured server name and roots.
  (test/cli/std_secure_dns_exercise.iyi)
* secure_dns.2 A TLS exchange writes all queries before reading answers and
  matches replies by ID, allowing reordered responses. Duplicate or unknown
  answer IDs without a waiting slot and truncated frames return malformed
  DnsError and close the connection. (test/cli/std_secure_dns_exercise.iyi)
* secure_dns.3 Successful TLS connections are retained until explicit close,
  failure or a subsequent exchange finding idle time greater than idle_ms,
  default 10,000. A reused connection that fails before receiving any answer is
  retried once on a fresh connection; partial frames are not retried. TLS
  session state retains tickets for resumption.
  (test/cli/std_secure_dns_exercise.iyi)
* secure_dns.4 DNS over HTTPS requires an https URL with a host and exactly GET
  or POST. A supplied numeric address bypasses DNS; otherwise a numeric host is
  used directly or the system resolver finds its first address once at
  construction. Bootstrap errors become exchange errors; exchanges do not
  resolve again. (test/cli/std_secure_dns_exercise.iyi)
* secure_dns.5 POST sends the message body with application/dns-message; GET
  appends an unpadded RFC 4648 base64url dns parameter. Both send Accept for
  that media type. Default TLS ALPN offers h2 then http/1.1; the HTTP client
  retains connections. (test/cli/std_secure_dns_exercise.iyi)
* secure_dns.6 DoH accepts only HTTP 200 and case-insensitive
  application/dns-message, allowing media parameters. Other statuses return
  refused DnsError, wrong media or bodies over 65,535 bytes return malformed
  DnsError, and transport failures return unreachable or timed-out DnsError.
  Cancellation propagates as Cancelled. (test/cli/std_secure_dns_exercise.iyi)
* secure_dns.7 The DoH zero_id? contract asks Resolver to use ID zero under RFC
  8484 section 4.1; DoT uses the given IDs. The transports send query bytes as
  supplied. Resolver provides RFC 7830 padding in 128-byte blocks under RFC
  8467; the transports add no padding themselves.
  (test/cli/std_secure_dns_exercise.iyi)
* secure_dns.8 Neither transport caches DNS records or applies HTTP cache
  lifetimes. Strict transport does not itself fall back to plaintext; fallback
  is the Resolver choice. Each upstream has a descriptive label and connection
  counters; close releases its retained network connections.
  (test/cli/std_secure_dns_exercise.iyi)
* secure_dns.9 Upstreams borrow configuration and identifying strings and own
  reusable transport state. Exchange stores copies of answer bytes through
  DnsLookup.keep and returns their views in caller replies; supplied reply
  storage is refilled. Callers close retained connections and obey SPEC 5.1 and
  5.6.
  <!-- todo: Needs proof -->

## semantic_version

Parses and orders Semantic Versioning 2.0.0 versions.

* semantic_version.1 The text grammar is major.minor.patch with optional
  dot-separated prerelease after dash and build after plus. Numeric core fields
  and numeric prerelease identifiers have no leading zeros; identifiers use
  ASCII letters, digits and dash, and cannot be empty. One final LF or CRLF is
  tolerated. (test/cli/std_semantic_version_exercise.iyi)
* semantic_version.2 valid? checks grammar without numeric conversion. parse?
  returns nil for invalid grammar or core fields outside Int32; parse panics on
  either. Direct construction rejects negative core fields but does not validate
  prerelease or build text. (src/std/semantic_version.iyi)
* semantic_version.3 Precedence follows SemVer 2.0.0 section 11: numeric core
  fields, releases after prereleases, numeric identifiers before nonnumeric,
  numbers by magnitude even beyond Int32, other identifiers bytewise and shorter
  equal-prefix lists first. Build metadata does not affect precedence.
  (test/cli/std_semantic_version_exercise.iyi)
* semantic_version.4 Equality requires equal precedence and equal build
  metadata; two builds can compare as zero in ordering yet be unequal.
  (test/cli/std_semantic_version_exercise.iyi)
* semantic_version.5 write appends canonical core numbers and held prerelease
  and build text, omitting empty prerelease and absent build. to_s and to_tape
  return that text under SPEC 1.5. Parsed prerelease and build borrow input
  slices; explicit retention uses SPEC 1.7. (src/std/semantic_version.iyi)

## set

Extends the prelude Set with set algebra, membership relations and Enumerable
operations.

* set.1 Union, also spelled plus, returns all receiver members in their order
  then new members from the other set. Intersection keeps common members in
  receiver order; symmetric difference keeps receiver-only then other-only
  members. Algebra leaves its operands unchanged.
  (test/cli/std_set_exercise.iyi)
* set.2 Union and symmetric difference accept different element types and return
  their union type. Intersection keeps the receiver element type; membership in
  the other set is false when its type cannot hold the value.
  (test/cli/std_set_exercise.iyi)
* set.3 Subset and superset compare membership, including reflexive and empty
  cases. Proper relations also require strictly different sizes. Disjoint means
  no common member; intersects is its negation. (test/cli/std_set_exercise.iyi)
* set.4 Equality compares sizes and membership independently of insertion order
  when either element type contains the other; otherwise it is false. Hash
  combines member hashes without depending on order so equal sets hash alike.
  (test/cli/std_set_exercise.iyi)
* set.5 Append and concat add members in place and return the receiver. dup
  creates a new set with the same members and order; results follow SPEC 1.5 and
  retain element references under SPEC 1.4. (test/cli/std_set_exercise.iyi)
* set.6 Importing this module also provides Enumerable operations through
  std/enumerable; iteration and conversion preserve set insertion order.
  (test/cli/std_set_exercise.iyi)

## shlex

Splits and quotes shell-style words with Python shlex POSIX-mode behavior.

* shlex.1 Splitting separates on ASCII space, tab, CR and LF. Adjacent unquoted,
  single-quoted and double-quoted fragments form one word, and an empty quoted
  fragment still forms an empty word. Single quotes preserve every byte until
  the closing quote. (test/cli/std_shlex_exercise.iyi)
* shlex.2 Outside quotes a backslash quotes the following byte, including LF.
  Inside double quotes it removes itself only before double quote or backslash;
  before other bytes it remains. These are Python shlex rules, differing from
  POSIX shell line continuation and dollar or backquote escapes.
  (test/cli/std_shlex_exercise.iyi)
* shlex.3 With comments enabled, an unquoted hash starts a comment even inside a
  word, ending at LF; otherwise hash is literal. No parameter, home, glob or
  command expansion occurs; shell operator characters are ordinary word
  characters and nothing is executed. (test/cli/std_shlex_exercise.iyi)
* shlex.4 Unclosed quotes and dangling backslashes return ShlexError with a
  message and the starting byte offset. UTF-8 bytes without ASCII syntax pass
  through unchanged; arbitrary NUL bytes can round-trip within the splitter but
  cannot be OS command arguments. (test/cli/std_shlex_exercise.iyi)
* shlex.5 quote leaves nonempty words containing only ASCII letters, digits and
  %+,-./:=@_ unquoted, writes empty as two single quotes and otherwise
  single-quotes the word, replacing each embedded quote with the standard
  single/double-quote splice. join places one space between quoted arguments.
  (test/cli/std_shlex_exercise.iyi)
* shlex.6 split(join(arguments)) reproduces the arguments. The String forms
  follow SPEC 1.5; builder forms append to caller output. Split words view newly
  decoded backing text, not the original input; retain them with SPEC 1.7.
  (src/std/shlex.iyi)

## signal

Waits for process signals as task values and changes their dispositions.

* signal.1 wait requires at least one signal and parks until a named signal
  arrives or returns Cancelled when its wait is cancelled. The first wait naming
  a signal installs handling in place of its default action; unnamed signals
  retain their disposition. (test/cli/std_signal_exercise.iyi)
* signal.2 After handling is installed, arrivals are retained even with no
  waiter, once per signal rather than counted. A wait takes the first pending
  signal in argument order. Only one fiber may park waiting at a time; a
  competing reader is refused. (test/cli/std_signal_exercise.iyi)
* signal.3 each invokes its block in the calling task for each consumed signal
  and returns Cancelled when waiting is cancelled. Arrivals during the block
  coalesce and remain pending for the next wait. No user block runs in the
  native signal handler, under SPEC 4.3. (test/cli/std_signal_exercise.iyi)
* signal.4 ignore drops pending arrivals and sets the named signals to be
  ignored. reset drops pending arrivals and restores defaults. A subsequent wait
  takes handling back. Neither operation supplies automatic scope-based
  restoration. (test/cli/std_signal_exercise.iyi)
* signal.5 The published enum supplies HUP, INT, QUIT, PIPE, ALRM, TERM, WINCH,
  CHLD, USR1 and USR2 with target signal numbers. Linux and Darwin record atomic
  pending bits and wake a nonblocking pipe; process-wide signal state needs no
  caller cleanup. (test/cli/std_signal_exercise.iyi)
* signal.6 Supported ris targets follow SPEC 7.1. In the inherited Windows
  implementation, INT maps Ctrl-C and Ctrl-Break, TERM maps console close,
  logoff and shutdown, other waits panic, and ignore or reset accepts INT only.
  Windows imposes its own shutdown deadline. (test/cli/std_signal_exercise.sh)

## slice

Provides bounded views and buffers of elements; Bytes is Slice(UInt8).

* slice.1 Pointer construction borrows size elements and rejects negative size.
  Size construction reserves caller-tape storage, optionally filling with a
  value or increasing-index block results. read_only is named and defaults
  false. Empty has size zero; byte size is size times sizeof(T).
  (test/cli/std_slice_exercise.iyi)
* slice.2 Element reads and writes support negative indices from the end.
  Required access panics out of bounds; optional access returns nil. Checked
  writes refuse read-only slices before writing.
  (test/cli/std_slice_exercise.iyi)
* slice.3 Offset addition gives the suffix for offsets zero through size.
  Start/count and range subslices alias elements and preserve the read-only
  flag; negative starts and endpoints count from the end. Negative counts and
  invalid bounds panic or return nil in optional forms; reversed ranges are
  empty at a valid start. (test/cli/std_slice_exercise.iyi)
* slice.4 Copy operations require sufficient source or destination bounds and
  nonnegative pointer counts. Slice destinations must be writable. Moves
  additionally handle overlapping regions in either direction; whole-slice copy
  and move leave extra destination elements unchanged.
  (test/cli/std_slice_exercise.iyi)
* slice.5 Fill, indexed fill, swap and reverse mutate the same storage and
  return the slice. They reject read-only receivers, even when empty; indexed
  operations check bounds. reverse_in_place is reverse.
  (test/cli/std_slice_exercise.iyi)
* slice.6 to_a copies elements in order to a new Array. dup and clone make a new
  shallow element buffer and retain the read-only flag, including for read-only
  sources; storage lifetime follows SPEC 1.5 and element references follow SPEC
  1.4. (test/cli/std_slice_exercise.iyi)
* slice.7 same? compares address and size, ignoring read-only state. Equality
  compares sizes and elements for the same element type, ignoring read-only
  state and padding; other types compare false. Hash comes from Indexable and
  follows element equality. (test/cli/std_slice_exercise.iyi)
* slice.8 Text and inspection use Bytes[...] for UInt8 and Slice[...] otherwise,
  with inspected elements separated by comma and space. hexstring emits
  lowercase two-digit bytes for UInt8 and panics for other element types.
  (test/cli/std_slice_exercise.iyi)
* slice.9 Iteration follows increasing indices; Indexable and Enumerable supply
  their collection operations. SliceIterator holds a shared cursor, returns
  successive elements and then Stop, and borrows the slice storage.
  (test/cli/std_slice_exercise.iyi)
* slice.10 to_unsafe, unsafe_fetch and unsafe_put expose unchecked storage
  access; unsafe_put also bypasses read-only protection. Their caller is
  responsible for pointer validity, lifetime and writable storage under SPEC
  5.4. Slices themselves require no close. (test/cli/std_slice_exercise.iyi)

## smtp

SmtpClient submits messages through an SMTP session using RFC 5321,
with optional TLS and authentication.

* smtp.1 connect requires a 220 greeting, sends EHLO, and falls back to HELO
  only after 500, 502 or 504. A caller-supplied greeting name is used, otherwise
  the local IP address literal; HELO records no extensions.
  (test/cli/std_smtp_exercise.iyi)
* smtp.2 STARTTLS is the default security mode and requires the extension. After
  its 220, buffered extra plaintext is refused, TLS verifies the host, and EHLO
  refreshes extensions. Implicit TLS starts before the greeting; Cleartext does
  no handshake (RFC 3207 and RFC 8314). (test/cli/std_smtp_exercise.iyi)
* smtp.3 AUTH chooses PLAIN, LOGIN then CRAM-MD5 from advertised mechanisms
  unless explicitly selected. An unadvertised mechanism fails. Without TLS it
  returns SmtpError unless cleartext_auth is set (RFC 4616 and RFC 2195).
  (test/cli/std_smtp_exercise.iyi)
* smtp.4 Malformed CRAM-MD5 challenges must return SmtpError rather than panic
  on server input.
  <!-- todo: AUTH passes the challenge to Base64.decode, which panics for
  invalid base64. -->
  <!-- todo: Needs proof -->
* smtp.5 Sending a Mail::Message uses From and all To, Cc and Bcc recipients and
  serializes without Bcc. Missing From, Date or recipients panics; raw sending
  rejects CR, LF, NUL and angle brackets in envelope addresses.
  (test/cli/std_smtp_exercise.iyi)
* smtp.6 The client requires SMTPUTF8 for non-ASCII envelope addresses or
  explicitly UTF-8 mail, and uses BODY=8BITMIME for non-ASCII data when offered.
  Non-ASCII data without either applicable extension is refused (RFC 6531, RFC
  6532 and RFC 6152). (test/cli/std_smtp_exercise.iyi)
* smtp.7 SIZE advertises and checks the message size after CRLF normalization,
  excluding transparency dots and the DATA terminator (RFC 1870).
  <!-- todo: send uses stuffed(data).bytesize, counting transparency and
  terminator; the existing SIZE test expects that incorrect count. -->
  <!-- todo: Needs proof -->
* smtp.8 MAIL requires 250; each RCPT requires 250 or 251 before DATA is sent. A
  refused recipient triggers RSET and returns a refusal. DATA requires 354, then
  a final 250; success returns nil. PIPELINING, CHUNKING and DSN are not
  implemented. (test/cli/std_smtp_exercise.iyi)
* smtp.9 DATA normalizes CRLF, CR and LF to CRLF, doubles leading dots and ends
  with a lone dot line. Empty data sends only the terminator. The builder
  overload appends; the String overload follows SPEC 1.5. (src/std/smtp.iyi)
* smtp.10 Replies have matching three-digit codes on every continuation line.
  Malformed replies, lines beyond 4096 bytes or replies beyond 100 lines fail
  and close the connection. SMTP refusals carry code and reply; transport
  failures use code zero and close. (test/cli/std_smtp_exercise.iyi)
* smtp.11 Read and write waits use timeout_ms, default 300000; errors
  distinguish timeout and cancellation. quit sends QUIT and closes, and close
  explicitly releases the transport. Reply-line views and retained session text
  belong to the session; callers obey SPEC 3.3.
  <!-- todo: Needs proof -->

## socket

This module provides stream sockets, IP address values and explicit
DNS resolvers over the platform socket interface.

* socket.1 IPv4 parsing accepts four decimal octets and localhost; IPv6 accepts
  compressed and bracketed forms and embedded IPv4 tails. IPv6 printing follows
  RFC 5952: lowercase, no leading zeros, the first longest zero run compressed,
  and a dotted mapped tail. (test/cli/std_udp_exercise.iyi)
* socket.2 Connecting without a Resolver accepts numeric addresses and localhost
  only; other hostnames panic naming the explicit resolver form. With a
  resolver, lookup errors become SocketError with unresolved? and a DnsError;
  cancellation propagates. (test/cli/std_dns_exercise.iyi)
* socket.3 Multiple addresses race under RFC 8305 with staggered attempts,
  normally 250 ms apart, accelerated by failure. Families alternate, preferring
  routed IPv6; localhost tries IPv4 first. The first success wins and every
  losing attempt closes before return. (test/cli/std_dns_exercise.iyi)
* socket.4 The connect timeout bounds all connection attempts together,
  excluding DNS lookup. Exhaustion reports timeout; failure of all addresses
  records their outcomes in attempted order. A single address reports its own
  error. (test/cli/std_dns_exercise.iyi)
* socket.5 listen binds numeric interfaces or localhost, with port zero
  selecting an ephemeral port. IPv6 listeners are IPv6-only. listen_result
  returns bind errors; listen panics for them. Unix stream factories use
  filesystem paths; their pathname limits and unsupported platforms are refused.
  (test/cli/socket_exercise.iyi)
* socket.6 accept waits for a connection; accept_ready returns nil if none is
  ready. Connected and accepted TCP sockets start with TCP_NODELAY enabled,
  adjustable with nodelay. (test/cli/socket_exercise.iyi)
* socket.7 read and recv return up to the requested byte count and empty text at
  EOF. String results are on the caller's tape; builder and Array forms write
  directly into checked caller storage. Negative counts and use after close
  panic. (test/cli/socket_exercise.iyi)
* socket.8 write and send borrow bytes until completion and return the complete
  count or an error or cancellation after possible partial output. Piece writes
  preserve concatenation order. Broken peers return SocketError without SIGPIPE.
  (test/cli/socket_exercise.iyi)
* socket.9 Read and write timeouts are per wait, leave the connection open and
  return SocketError with timed_out?. Unset timeouts wait indefinitely.
  Cancellation, or closure while parked, wakes the call with Cancelled.
  (test/cli/socket_exercise.iyi)
* socket.10 Socket aliases share descriptor state. close is idempotent and
  closes the descriptor; close_write shuts only the sending half. Local address
  and port describe the binding, remote accessors return nil when no peer is
  available. Resource ownership follows SPEC 5.1. (test/cli/socket_exercise.iyi)
* socket.11 Resolvers check literal addresses and hosts text before DNS, then
  use the search list and ndots. A records precede AAAA; a successful A answer
  survives an AAAA failure. CNAME chains are bounded; truncated UDP answers
  retry over TCP. (test/cli/std_dns_exercise.iyi)
* socket.12 read_system and read_files refill resolver configuration; missing
  files read as empty. refill copies lists and text into resolver-owned storage
  and skips unusable configured servers. Explicit construction rejects invalid
  server addresses, nonpositive timeout or attempts and negative ndots.
  (test/cli/std_dns_exercise.iyi)
* socket.13 Encrypted upstreams replace plaintext servers. Plaintext fallback is
  disabled unless requested, and then occurs only when no upstream could answer,
  not after an answered DNS refusal. close closes upstream connections; the next
  exchange can reopen them. (test/cli/std_secure_dns_exercise.iyi)
* socket.14 TXT lookup appends joined character strings into caller-supplied
  lists and text storage without search expansion or hosts lookup. HTTPS-record
  lookup writes its answer into the supplied SvcbStore. Results and diagnostic
  retention follow SPEC 1.5 and 1.7. (test/cli/std_dns_exercise.iyi)
* socket.15 Simultaneous reads on one descriptor, or simultaneous writes, are
  refused. One reader and one writer may progress independently where resource
  ownership under SPEC 5.1 permits it. (test/cli/socket_exercise.sh)

## sse

SSE parses, emits and reconnects server-sent event streams following
the WHATWG HTML Living Standard section 9.2.

* sse.1 EventParser accepts arbitrary byte pieces, replaces maximal malformed
  UTF-8 subparts, drops one initial BOM and recognizes CR, LF and CRLF,
  including across feeds. Comments and unknown field names are ignored.
  (test/cli/std_sse_exercise.iyi)
* sse.2 Fields split at the first colon and drop one following space. data lines
  join with LF and dispatch at a blank line with the last LF removed; no data
  means no event. Missing event type becomes message. finish discards an
  unfinished line or event. (src/std/sse.iyi)
* sse.3 IDs persist across events and reconnects; an id containing NUL is
  ignored. A blank line updates last_event_id even without data. retry accepts
  only nonempty ASCII digits and saturates at 2147483647 milliseconds.
  (src/std/sse.iyi)
* sse.4 Events passed to feed callbacks view parser-owned builders, reused after
  the callback. Retaining their type, data or ID requires SPEC 1.7; parser input
  is copied into reusable line storage.
  <!-- todo: Needs proof -->
* sse.5 encode writes optional event, id and retry fields, one data field per
  normalized line and a terminating blank line. comment writes colon lines.
  Builder forms append; String forms build under SPEC 1.5. (src/std/sse.iyi)
* sse.6 Emission refuses non-UTF-8 text, line breaks in event types, line breaks
  or NUL in IDs, and negative retry. Refusal happens before output.
  (test/cli/std_sse_exercise.iyi)
* sse.7 stream writes status 200 and text/event-stream, defaults Cache-Control
  to no-cache and preserves an existing cache directive. An existing
  Content-Type panics. Each EventWriter operation is one immediate body chunk; a
  write failure is retained and gone? reports it.
  (test/cli/std_sse_exercise.iyi)
* sse.8 open makes GET requests accepting text/event-stream and sends a safe
  nonempty Last-Event-ID. A non-200 response or wrong media type returns
  SSEError without reconnecting; media-type parameters and case are accepted.
  Callback false stops and closes. (test/cli/std_sse_exercise.iyi)
* sse.9 Ended or failed connections reconnect after retry, initially 3000 ms.
  More than reconnects consecutive connections without events returns the last
  failure; the default permits five reconnections. Any event resets the count;
  Cancelled returns immediately. No exponential backoff, CORS or browser
  credentials policy is supplied. (test/cli/std_sse_exercise.iyi)

## static_array

Fixed-size arrays hold N elements inline and provide checked access,
iteration, searching and sorting.

* static_array.1 Construction fills all N positions with one value or the block
  result for each index; size and count without an argument are N.
  (test/cli/std_static_array_exercise.iyi)
* static_array.2 Checked indexing and assignment accept negative indices counted
  from the end. Out-of-range access panics; []? returns nil, including for an
  index wider than Int32. Empty first and last panic; their ? forms return nil.
  (test/cli/std_static_array_exercise.iyi)
* static_array.3 fill changes all elements or the requested range. A negative
  start counts from the end; a negative count or start outside 0..N panics
  before mutation. A count beyond the end fills only the remaining elements.
  (test/cli/std_static_array_exercise.iyi)
* static_array.4 Iteration visits elements in order, reverse_each in reverse
  order. Indexed iteration and mapping add the supplied offset to each index.
  Mapping returns another fixed-size array.
  (test/cli/std_static_array_exercise.iyi)
* static_array.5 sort and sort_by return copies; their in-place forms replace
  the elements. Sorting is stable, including the unstable_sort aliases, and
  sort_by computes each key once. (test/cli/std_static_array_exercise.iyi)
* static_array.6 Rotation moves elements left by the count modulo N, with
  negative counts rotating right; reversal changes their order. dup and clone
  copy the element slots without deep-copying referenced data.
  (test/cli/std_static_array_exercise.iyi)
* static_array.7 index and rindex search from their checked offsets and return
  nil on a miss. find returns the first matching element. Membership, truth
  predicates and count(item) inspect the elements.
  (test/cli/std_static_array_exercise.iyi)
* static_array.8 Equality compares lengths and corresponding values for
  compatible element types. Ordering is lexicographic for the same array type;
  equal arrays hash alike. Inspection writes StaticArray[ followed by inspected
  elements separated by commas and a closing ].
  (test/cli/std_static_array_exercise.iyi)
* static_array.9 to_slice views writable inline storage; to_a copies slots to a
  caller-tape Array under SPEC 1.5. Neither conversion deep-copies elements.
  Unsafe fetch, put and pointer access omit bounds checks.
  <!-- todo: Needs proof -->

## steppable

Numeric stepping visits values by repeated addition, with an optional
limit. Int32, Int64 and Float64 implement Steppable.

* steppable.1 The iterator yields the start, then successive additions of by,
  stopping before crossing the limit. An exclusive limit is not yielded; a step
  pointing away from the limit yields nothing.
  (test/cli/std_steppable_exercise.iyi)
* steppable.2 When start equals limit, inclusive stepping yields it once and
  exclusive stepping yields nothing, even for a zero step. Any other zero step
  panics with zero step size. (test/cli/std_steppable_exercise.iyi)
* steppable.3 A bounded floating walk with NaN in its start, limit or step is
  empty. A step producing an unordered next value or remaining distance stops
  the bounded walk. (test/cli/std_steppable_exercise.iyi)
* steppable.4 Bounded integer walks check room before an addition that would
  overflow. Bounded floating walks use the limit-minus-step comparison,
  preserving the rounding of repeated addition.
  (test/cli/std_steppable_exercise.iyi)
* steppable.5 With no limit the iterator keeps adding until the caller stops or
  arithmetic fails. Stop remains Stop on subsequent reads; sum consumes the
  remaining values into its initial accumulator.
  (test/cli/std_steppable_exercise.iyi)
* steppable.6 The block form visits the same values as the iterator and returns
  Nil. Custom element types supply addition, subtraction, ordering and
  comparison of the step with zero. Iterator storage follows SPEC 1.3.
  (test/cli/std_steppable_exercise.iyi)

## string_pool

StringPool interns byte strings in storage owned by the pool.

* string_pool.1 get returns the stored String for equal bytes and increases size
  only for previously absent bytes. empty? is true exactly when size is zero.
  (test/cli/std_string_pool_exercise.iyi)
* string_pool.2 get copies new text once into the pool's builder; returned
  Strings view that storage, independent of the input lifetime. Existing entries
  remain valid across insertion and rehash under SPEC 2.2.
  <!-- todo: Needs proof -->
* string_pool.3 get? returns an existing entry or nil without inserting it.
  <!-- todo: Needs proof -->
* string_pool.4 Capacity starts at a power of two of at least eight, no smaller
  than the requested initial capacity. Insertion doubles it at three-quarters
  occupancy; explicit rehash doubles it without removing entries.
  <!-- todo: Needs proof -->

## string_scanner

StringScanner matches and searches borrowed text while tracking a byte
offset and the most recent match.

* string_scanner.1 The offset starts at zero and may be set from zero through
  bytesize only at a character boundary. Invalid positions panic. rest views the
  remaining input and eos? reports its end.
  (test/cli/std_string_scanner_exercise.iyi)
* string_scanner.2 scan and skip match at the current offset; their until forms
  search forward and consume through the match. Failure returns nil without
  moving. scan returns the consumed input view; skip returns its byte length.
  (test/cli/std_string_scanner_exercise.iyi)
* string_scanner.3 check, check_until and matches? record a match without
  moving. matches? returns its byte length. Every failed match clears the
  previous match. (test/cli/std_string_scanner_exercise.iyi)
* string_scanner.4 String and Char patterns compare bytes; Regex uses the whole
  input and its offset, so anchors still refer to the original start and word
  boundaries see preceding text. (test/cli/std_string_scanner_exercise.iyi)
* string_scanner.5 Integer scan, skip and check counts mean characters and fail
  when fewer remain; peek returns up to that many without changing the match.
  Negative counts panic. Each malformed UTF-8 byte counts as one replacement
  character. (test/cli/std_string_scanner_exercise.iyi)
* string_scanner.6 Group zero is the matching span, excluding any preceding text
  consumed by an until form. Regex groups accept numbers, negative indices and
  names. Missing or unmatched groups panic with []; []? returns nil. Other
  patterns have group zero only. (test/cli/std_string_scanner_exercise.iyi)
* string_scanner.7 reset moves to zero and terminate moves to the end; both
  clear the match. Inspection shows byte position and length with a short
  escaped character window around the position.
  (test/cli/std_string_scanner_exercise.iyi)
* string_scanner.8 The scanner borrows its input; returned substrings and groups
  view that input. Capture slots are copied into reusable scanner storage, not
  retained from a temporary match. Retention follows SPEC 1.7.
  <!-- todo: Needs proof -->

## symbol

This module adds ordering and printable literal forms to Symbol.

* symbol.1 Symbols order by the byte ordering of their text; <=> returns -1, 0
  or 1. clone returns the same symbol. (test/cli/std_symbol_exercise.iyi)
* symbol.2 inspect prefixes a colon and leaves supported operators, underscore
  and ASCII identifiers unquoted. Identifiers may end in one question mark or
  exclamation mark. Other spellings use a double-quoted body.
  (test/cli/std_symbol_exercise.iyi)
* symbol.3 Quoted bodies escape quotes, backslashes, interpolation openers,
  named ASCII controls and other controls or DEL as uppercase hexadecimal
  Unicode escapes. Other bytes remain unchanged.
  (test/cli/std_symbol_exercise.iyi)
* symbol.4 A named-argument key is quoted when empty, underscore, digit-leading
  or containing anything outside ASCII letters, digits and underscore. IO forms
  write the same text as String forms. (test/cli/std_symbol_exercise.iyi)
* symbol.5 Escaping without changes may return the input view; newly built text
  follows SPEC 1.5. The builder overload appends to the supplied builder.
  <!-- todo: Needs proof -->

## system

System reads the machine hostname, process CPU allowance and page size.

* system.1 hostname reads the current kernel node name on each call and returns
  copied text on the caller's tape under SPEC 1.5.
  (test/cli/std_system_exercise.iyi)
* system.2 On Linux cpu_count counts the current affinity mask, falling back to
  the online CPU list when affinity cannot be read. On Darwin it asks active
  CPUs then logical CPUs. It never invents a count when both sources fail.
  (test/cli/std_system_exercise.iyi)
* system.3 page_size returns and caches the kernel page size, using AT_PAGESZ on
  Linux and getpagesize on Darwin. It does not assume 4096-byte pages.
  (test/cli/std_system_exercise.iyi)
* system.4 Failure to obtain required system information panics with the failed
  source. The supported build targets remain those of SPEC 7.1.
  <!-- todo: Needs proof -->

## system_roots

SystemRoots loads operating-system trust anchors into an owned
certificate store for X509 verification.

* system_roots.1 read_system clears the previous store, unreadable count and
  source, advances its generation, and marks a successful nonempty load. A load
  with no usable certificate returns X509Error.
  (test/cli/std_system_roots_exercise.iyi)
* system_roots.2 Nonempty SSL_CERT_FILE or SSL_CERT_DIR overrides platform
  defaults. The file and all files in the listed directories are read; directory
  lists use colon on POSIX. Directory entries are visited in sorted order.
  (test/cli/std_system_roots_exercise.iyi)
* system_roots.3 Linux tries the configured distribution bundles in order and
  uses the first containing readable certificates, otherwise scanning
  /etc/ssl/certs and /etc/pki/tls/certs.
  (test/cli/std_system_roots_exercise.iyi)
* system_roots.4 Darwin combines system anchors with administrator then user
  trust settings. Unconstrained root trust can add certificates; denial removes
  them, including a constrained denial. Constrained positive trust adds nothing.
  (test/cli/std_system_roots_exercise.iyi)
* system_roots.5 Duplicate DER certificates are kept once. Unreadable
  certificates increment unreadable rather than failing the whole load; denied
  certificates are not added. (test/cli/std_system_roots_exercise.iyi)
* system_roots.6 Certificate payloads are copied into the store's buffers and
  views remain tied to that owner. Reloading clears those buffers; callers obey
  SPEC 3.3. source describes where loading looked; platform handles are released
  internally.
  <!-- todo: Needs proof -->

## tar

TarReader and TarWriter stream POSIX ustar and pax archives, with
legacy GNU and v7 reading and optional compression.

* tar.1 next_entry reads sequential 512-byte headers and skips unread prior data
  and padding. Entry reads apply only to the current entry, return up to the
  requested positive count and empty at entry EOF; nonpositive reads and reading
  an expired entry panic. (test/cli/std_tar_exercise.iyi)
* tar.2 Readers detect gzip, bzip2 and xz by their leading bytes. A zero block
  or EOF at a block boundary ends an archive. Compressed input is drained after
  the archive end so trailer and container checks can still fail.
  (test/cli/std_tar_exercise.iyi)
* tar.3 Headers require the unsigned POSIX checksum or the legacy signed
  checksum. POSIX prefix names, GNU long names and targets, octal and GNU
  base-256 numbers are read. Malformed numbers, negative sizes, truncated
  headers or data return TarError. (test/cli/std_tar_exercise.iyi)
* tar.4 Local and global pax records override path, linkpath, size, mtime, uid,
  gid, uname and gname; unknown records remain available. Fractional mtime is
  retained to nanoseconds. Pax and GNU extension payloads above 1 MiB and
  extensions without a following entry fail. (test/cli/std_tar_exercise.iyi)
* tar.5 A reader retains failure and subsequent operations return it. read_all
  refuses content beyond the String size limit and names streaming read as the
  alternative. The current entry and its metadata view reusable reader storage;
  output Strings follow SPEC 1.5. (test/cli/std_tar_exercise.iyi)
* tar.6 Extraction accepts regular files, directories, symbolic links and hard
  links. It rejects absolute names and .. components, escaping or
  descending-then-ascending symlink targets, and traversal through existing
  symlinks. Hard links require an earlier extracted regular file; devices and
  FIFOs fail. (test/cli/std_tar_exercise.iyi)
* tar.7 Extraction replaces existing files, applies ordinary permission bits
  without setuid, setgid or sticky, and restores mtime. Validation occurs entry
  by entry; failure leaves earlier extracted entries in place. Windows separator
  and drive spellings are additionally refused where applicable.
  (test/cli/std_tar_exercise.iyi)
* tar.8 Writing emits ustar plus pax when fields do not fit or require non-ASCII
  text. It writes regular files, directories and symbolic and hard links;
  streamed content requires an explicit nonnegative size and premature source
  EOF panics. Modification times are emitted in whole seconds.
  (test/cli/std_tar_exercise.iyi)
* tar.9 finish emits two zero blocks and pads to 10240 bytes, finishes optional
  gzip encoding and flushes the sink. It does not close source or sink. Double
  finish, adding after finish, empty names, absolute names and NUL in names
  panic. (test/cli/std_tar_exercise.iyi)
* tar.10 GNU and v7 output, sparse reconstruction, ACLs, extended attributes,
  multi-volume archives, append mode, bzip2 writing and xz writing are not
  implemented. Sparse declarations are metadata only, not hole reconstruction.
  (test/cli/std_tar_exercise.iyi)

## term

Term probes terminals, changes their input modes for a block and
reads passwords with echo disabled.

* term.1 tty? accepts a stream or descriptor and reports whether the platform
  recognizes a terminal. Closed streams report false. size returns rows then
  columns, or nil for nonterminals and zero dimensions. Without an argument it
  tries stdout, stderr then stdin. (test/cli/std_term_exercise.iyi)
* term.2 raw runs a block with echo, canonical input, signal generation and
  CR/LF translations disabled, following termios cfmakeraw on POSIX. One byte
  suffices for input. It returns the block value or TermError without running
  the block when setup fails. (test/cli/std_term_exercise.iyi)
* term.3 no_echo disables ECHO, ECHOE, ECHOK and ECHONL on POSIX while
  preserving other settings. Mode changes use immediate application without
  flushing queued input; saved settings are restored by defer according to SPEC
  4.1. Closed-stream mode changes panic. (test/cli/std_term_exercise.iyi)
* term.4 Restoration failure must be reported rather than silently leaving the
  terminal in its temporary mode.
  <!-- todo: with_mode defers set_mode but discards the returned platform
  error. -->
  <!-- todo: Needs proof -->
* term.5 read_password writes its prompt to stderr, reads stdin in canonical
  mode with echo off, writes a newline and returns the line without its ending,
  or nil at EOF. Nonterminal stdin is read directly. A failure to disable echo
  panics instead of exposing the password. (test/cli/std_term_exercise.iyi)
* term.6 TermError identifies operation, descriptor, platform code and whether
  the stream was a terminal. Returned password text follows SPEC 1.5; no stream
  is closed by these helpers. (test/cli/std_term_exercise.iyi)

## text

This compatibility module adds no methods: text operations live in
the tape String and Char core.

* text.1 Importing std/text leaves String and Char operations in the core;
  storage and substring views follow SPEC 7.2 and 1.5.
  <!-- todo: Needs proof -->
* text.2 Core text operations exercised here recognize Unicode whitespace in
  blank? and numeric conversion, and strip specified non-ASCII characters.
  (src/std/text.iyi)
* text.3 Core translation replaces selected characters, squeeze collapses
  repeated characters, and block gsub substitutes matching text with the block
  result. (src/std/text.iyi)

## time

Time represents instants with locations; Span represents durations.
The module provides clocks, civil arithmetic, zones and text formats.

* time.1 Time stores Unix seconds and a normalized nanosecond fraction. UTC and
  Unix constructors use UTC; local constructors use a supplied or machine
  location. Comparison and hashing use the instant alone, while calendar fields
  use its location. (test/cli/std_time_exercise.iyi)
* time.2 Calendar constructors use proleptic Gregorian leap-year rules and
  reject invalid months, days, hours, minutes, seconds or fractions. Seconds are
  0..59: leap seconds are not represented. Millisecond and nanosecond arguments
  together must remain below one second. (test/cli/std_time_exercise.iyi)
* time.3 DayOfWeek numbers Monday as one through Sunday as seven and refuses any
  other number. Day and year calculations include ISO week dates and enforce
  valid ISO week and weekday ranges. (test/cli/std_time_exercise.iyi)
* time.4 Span combines duration units, normalizes signed seconds and
  nanoseconds, exposes integer components and floating totals, and supports
  addition, subtraction, negation, comparison and hashing. Overflow of its Int64
  seconds panics with a span-specific diagnostic.
  (test/cli/std_time_exercise.iyi)
* time.5 utc and local read the wall clock; monotonic returns an elapsed-clock
  Span suitable for differences, not a civil instant. No elapsed-clock epoch is
  promised. (test/cli/std_time_exercise.iyi)
* time.6 Adding or subtracting Span changes elapsed time; subtracting instants
  returns Span. shift applies years and months with end-of-month clamping, then
  calendar weeks and days in the location, then elapsed smaller units.
  Out-of-range shifted years and durations panic.
  (test/cli/std_time_exercise.iyi)
* time.7 Location loads IANA TZif data under RFC 8536 from system directories or
  ZONEINFO and returns LocationError for missing or malformed data. Absolute,
  parent-traversing, backslash and NUL names are refused. Fixed locations use
  the supplied offset and optional name. (test/cli/std_time_exercise.iyi)
* time.8 For repeated local times the earlier instant is chosen. A skipped local
  time is read using the pre-change clock, moving forward past the gap. Changing
  an instant's location preserves that instant. (test/cli/std_time_exercise.iyi)
* time.9 Time::Format writes and parses numeric calendar fields, English names,
  ISO week fields, fractions, epoch seconds, UTC or numeric offsets and
  composite strftime directives. Literal bytes must match; pattern whitespace
  accepts any run, including empty. Numeric padding and uppercase-name flags are
  supported. (test/cli/std_time_exercise.iyi)
* time.10 Format parsing returns Time or TimeParseError containing input and
  zero-based byte position. It rejects out-of-range fields and trailing text;
  weekday names are validated but not checked against the date. A missing zone
  needs a supplied offset or location. (test/cli/std_time_exercise.iyi)
* time.11 Named formats cover RFC 3339, RFC 2822, ISO 8601 date-time and the
  three RFC 9110 HTTP-date forms. parse_rfc3339 panics on invalid input; the
  underlying format parser and other named parsers return TimeParseError.
  Unknown zone abbreviations are not resolved to IANA locations.
  (test/cli/std_time_exercise.iyi)
* time.12 RFC 3339 formatting writes location offsets and requested fractional
  digits; the reader also accepts a space separator and signed or extended years
  beyond the RFC's four-digit grammar. Formatting and parsing use nanosecond
  precision. (src/std/time.iyi)
* time.13 Formatting builds caller-tape text or appends to a supplied builder
  under SPEC 1.5. Parse errors borrow their input; Format borrows its pattern.
  Locations retain their parsed transition data, so keeping locations or their
  views obeys SPEC 3.2.
  <!-- todo: Needs proof -->

## tls

TLS supplies client and server transports using RFC 8446 TLS 1.3,
with explicitly enabled TLS 1.2 and bounded session state.

* tls.1 Both ends default to TLS 1.3 and refuse older peers. min_version TLS12
  additionally permits TLS 1.2 under RFC 5246 with extended master secret, ECDHE
  and AEAD only; no CBC, RC4, static RSA exchange or TLS 1.2 resumption is
  supplied. (test/cli/std_tls_exercise.iyi)
* tls.2 TLS 1.3 supports AES-128-GCM/SHA-256, AES-256-GCM/SHA-384 and
  ChaCha20-Poly1305/SHA-256. Key exchange supports X25519, secp256r1, secp384r1
  and the TLS 1.3-only X25519MLKEM768 hybrid of draft-ietf-tls-ecdhe-mlkem-05.
  Malformed shares, small-order X25519 inputs and invalid ML-KEM keys are
  refused. (test/cli/std_tls_exercise.iyi)
* tls.3 The client offers hybrid and X25519 shares by default; post_quantum
  false omits the hybrid. HelloRetryRequest may request an offered group whose
  share was not sent or a cookie. Unoffered groups and repeated already-sent
  shares are refused. Server configured group order determines selection.
  (test/cli/std_tls_exercise.iyi)
* tls.4 Clients always verify the server chain and hostname with X509, using
  explicit roots or config-owned system roots, then verify CertificateVerify and
  Finished. Certificate checking cannot be disabled. TLS 1.3 uses ECDSA, RSA-PSS
  or Ed25519 signatures, never PKCS #1 v1.5 CertificateVerify.
  (test/cli/std_tls_exercise.iyi)
* tls.5 TLS 1.2 requires extended master secret, checks downgrade sentinels,
  matches certificate kind to the selected ECDHE suite and verifies signed
  parameters and Finished. Its suite set is ECDHE_RSA or ECDHE_ECDSA with the
  same three AEAD families. Renegotiation is refused; no KeyUpdate exists in
  that version. (test/cli/std_tls_exercise.iyi)
* tls.6 TlsIdentity reads leaf-first PEM chains and matching Ed25519, P-256,
  P-384 or RSA private keys in supported PKCS #8, SEC 1 or PKCS #1 forms.
  Mismatched keys and RSA keys below 2048 bits fail. Reusable identity loading
  copies certificate and private-key payloads into identity-owned storage.
  (test/cli/std_tls_exercise.iyi)
* tls.7 The server selects a compatible identity for SNI, falling back to its
  configured identity. A TlsIdentitySource may override that selection or return
  an error; nil preserves normal selection. It receives offered ALPN and the
  remaining deadline. Proc sources are refused in favor of the explicit trait.
  (test/cli/std_tls_exercise.iyi)
* tls.8 ALPN follows RFC 7301: the client offers protocols and the server
  selects by its preference. A server configured with protocols refuses an
  offered list with no match. Negotiated version, group, protocol, server name
  and peer certificates remain observable. (test/cli/std_tls_exercise.iyi)
* tls.9 A client identity answers compatible certificate requests. Server
  client_roots enables clientAuth chain and signature checks; absence of a
  certificate fails unless client_required is false. Resumed sessions retain the
  originally authenticated peer certificates. (test/cli/std_tls_exercise.iyi)
* tls.10 Handshake waits default to a 30000 ms deadline. TlsError carries a
  reason, optional alert, timeout and cancellation flags, and optional ECH retry
  data. Protocol failures send an appropriate alert where possible and close. An
  identity source must bound its own waits: its execution is not interrupted by
  the handshake deadline. (test/cli/std_tls_exercise.iyi)
* tls.11 read returns at most a positive requested count and empty only for
  close_notify. Nonpositive reads panic. Builder and Array forms copy plaintext
  into caller storage; String forms build caller-tape results under SPEC 1.5.
  Record buffers are connection-owned. (test/cli/std_tls_exercise.iyi)
* tls.12 write borrows plaintext and returns a byte count or TlsError, with
  possible partial transmission on failure. Records carry at most 16384 content
  bytes; TLS 1.3 inner plaintext is at most 16385 bytes. Fragmented handshake
  messages cannot interleave other record types. (test/cli/std_tls_exercise.iyi)
* tls.13 TLS 1.3 answers requested KeyUpdates before later application writes
  and automatically updates at key_limit, default 8388608 records. Explicit
  key_update may request the peer to update. TLS 1.2 refuses explicit updates
  and ends writes when its per-key record limit is reached.
  (test/cli/std_tls_exercise.iyi)
* tls.14 close_write sends close_notify and shuts the sending half while
  permitting reads. close drains until peer close, transport end, a one-second
  idle gap, ten seconds total or 64 MiB, then closes. abort closes immediately.
  TLS 1.2 peer close_notify also ends writes. Resource ownership follows SPEC
  5.1. (test/cli/std_tls_exercise.iyi)
* tls.15 export_keying_material derives caller-tape key bytes bound to the
  connection, label and context, using RFC 8446 section 7.5 or RFC 5705 for TLS
  1.2. Empty context in TLS 1.2 means no context. TlsKeySchedule and
  TlsRecordCipher expose schedule and record operations for trace verification.
  (test/cli/std_tls_exercise.iyi)
* tls.16 TlsSession holds at most eight tickets, each at most 16 KiB, bounded by
  its clamped configured count. It offers the newest matching ticket once, for
  the same host, port and trust configuration while certificate validity, ticket
  lifetime and seven days since original authentication still permit it.
  (test/cli/std_tls_exercise.iyi)
* tls.17 Server resumption uses authenticated encrypted tickets and psk_dhe_ke
  only. Ticket binders, names, age, hash and lifetime are checked; untaken
  tickets fall back to a full handshake. TlsTicketKeys rotates secure
  process-local keys, sealing for one period and opening for one more;
  restarting loses tickets. (test/cli/std_tls_exercise.iyi)
* tls.18 Early data is opt-in, at most 256 KiB. Acceptance requires the first
  PSK identity, matching suite and protocol, no HelloRetryRequest, age within
  ten seconds and replay-guard admission. read_early exposes it separately;
  finish checks the remaining client handshake. Rejected client early data is
  sent later only when the negotiated protocol permits it.
  (test/cli/std_tls_exercise.iyi)
* tls.19 TlsReplayGuard remembers admitted binders for two windows and rejects
  duplicates or capacity exhaustion, default 65536 entries. It does not prevent
  application retries or coordinate separate processes; early requests must
  tolerate replay. (test/cli/std_tls_exercise.iyi)
* tls.20 OCSP stapling is requested and any supplied staple is checked for the
  leaf, signer and freshness. Revoked and unknown responses fail. require_staple
  and RFC 7633 must-staple reject absence; servers send configured staples only
  while current. No CRL or network responder lookup is performed.
  (test/cli/std_tls_exercise.iyi)
* tls.21 RFC 9849 ECH encrypts the inner name, ALPN and PSK using a supported
  ECHConfig and HPKE suite; default no-config clients send GREASE unless
  disabled. ECH with TLS 1.2 is refused. Acceptance is confirmed, including
  after retry; rejection verifies the public name then returns ech_required and
  retry_configs. Split mode and extra ALPN padding profiles are not provided.
  (test/cli/std_tls_exercise.iyi)
* tls.22 Configs, sessions, identities, replay guards and connections hold
  owner-local mutable state under SPEC 2.1 and 5.3. TlsConfig.refill copies
  protocol text and ECH bytes, while borrowing roots and identity. System roots
  are cached until explicit refresh, with failed loads retried; dup is refused
  and names refill.
  <!-- todo: The roots property comment says each handshake reloads roots;
  trusted_roots actually caches a successful load until read_system. -->
  <!-- todo: Needs proof -->

## toml

TOML parses and emits TOML 1.0.0 documents and converts typed values
through TapeAny and derive toml_serializable.

* toml.1 parse returns a table-valued TapeAny or TOMLError; parse? returns nil
  on failure. Error line and character column count from one. Invalid document
  bytes return errors rather than panicking. (test/cli/std_toml_exercise.iyi)
* toml.2 Keys support bare ASCII letters, digits, underscore and dash,
  single-line quoted forms and dotted paths. Keys are always strings. Explicit
  tables, implicit super-tables and arrays of tables follow TOML 1.0.0
  redefinition rules. Duplicate keys and incompatible redefinitions fail.
  (test/cli/std_toml_exercise.iyi)
* toml.3 Strings support basic, literal and multiline forms, TOML 1.0 escapes
  and Unicode scalar escapes. Multiline opening newlines are dropped, CRLF
  becomes LF and basic-string line continuations trim following whitespace.
  Invalid escapes, controls and unterminated strings fail.
  (test/cli/std_toml_exercise.iyi)
* toml.4 Integers are Int64, decimal with optional sign or unsigned 0x, 0o and
  0b forms. Underscores occur only between digits; decimal leading zeros and
  overflow fail. Floats are Float64 with fractions or exponents, inf and nan;
  true and false are booleans. (test/cli/std_toml_exercise.iyi)
* toml.5 Dates retain offset date-time, local date-time, local date or local
  time as distinct TOMLDateTime kinds. Fractional digits after nine are
  truncated. Invalid calendar fields, leap seconds and offsets beyond 23:59
  fail; local forms do not invent missing dates, times or offsets.
  (test/cli/std_toml_exercise.iyi)
* toml.6 TOMLDateTime equality includes kind and fields, retaining the original
  offset. unix_seconds is available only for offset date-times. Construction
  rejects fields inconsistent with its kind; formatting writes that kind back.
  (test/cli/std_toml_exercise.iyi)
* toml.7 Arrays may mix types, span lines and end with a trailing comma. Inline
  tables stay on one line, allow no trailing comma and cannot be extended later.
  Nesting beyond 64 levels fails, counting table paths and collection values.
  (test/cli/std_toml_exercise.iyi)
* toml.8 Malformed UTF-8, BOMs, unsupported escapes, bare CR, forbidden controls
  and unfinished constructs return TOMLError with a location. TOML 1.1-only
  syntax is not accepted. (test/cli/std_toml_exercise.iyi)
* toml.9 TapeAny provides checked and nilable casts, table and array indexing,
  negative array indices and dig traversal. Float casts widen integers; integer
  casts do not narrow floats. size on Strings counts bytes. Equality is
  structural, distinguishes integer and float, equates NaNs, and agrees with
  hash. (test/cli/std_toml_exercise.iyi)
* toml.10 dump requires a table and panics for any other root. It writes scalar
  assignments before child table headers and nonempty homogeneous arrays of
  tables as repeated headers; nested tables in ordinary arrays are inline. Keys
  and Strings are escaped and quoted as required.
  (test/cli/std_toml_exercise.iyi)
* toml.11 Dumped finite floats round-trip to the same double and retain their
  float kind; infinities and NaNs use TOML spellings. A nonempty document ends
  in a newline. Builder overloads append; String output follows SPEC 1.5.
  (test/cli/std_toml_exercise.iyi)
* toml.12 Typed conversion supports scalars, date-times, TapeAny, arrays,
  String-keyed hashes, nilable types and ToTOML types. Incompatible values and
  out-of-range narrowing panic. TOML has no null: nil outside omitted derived
  fields and UInt64 beyond Int64::MAX cannot be emitted.
  (test/cli/std_toml_exercise.iyi)
* toml.13 Derived types map fields to keys in declaration order, ignore unknown
  keys, preserve defaults for missing fields, and use nil for missing nilable
  fields. Missing required fields fail by name. Nil fields are omitted when
  written. (test/cli/std_toml_exercise.iyi)
* toml.14 Parsing builds pool-backed arrays and tables in the caller's
  destination; text may view input or parser-owned decoded text. Conversion
  overloads may use caller-supplied pools. Explicit copy_to retains independent
  values according to SPEC 1.7. (src/std/toml.iyi)

## traits

Comparable, Num and Hashable supply common contracts for comparisons,
arithmetic folds and hash keys.

* traits.1 Comparable derives equality and the four ordering predicates from the
  sign of <=>. between? includes both endpoints.
  <!-- todo: Needs proof -->
* traits.2 clamp returns max when above it, min when below it, and self
  otherwise. A range argument must be inclusive; an exclusive range panics.
  <!-- todo: Needs proof -->
* traits.3 Num requires type-level zero and one and value-level add and mul.
  Implementations on supported integers and floats use their native addition and
  multiplication.
  <!-- todo: Needs proof -->
* traits.4 Integer three-way comparison returns -1, 0 or 1 without subtracting
  operands. String and Char ordering similarly derive from their native
  comparisons.
  <!-- todo: Needs proof -->
* traits.5 Hashable requires an Int32 hash_key. The supplied scalar, tuple,
  named-tuple, Array, Nil and Symbol implementations forward to hash; Bool uses
  1231 for true and 1237 for false. Supporting numeric and tuple modules are
  imported with the trait.
  <!-- todo: Needs proof -->

## tuple

Tuple and NamedTuple operations preserve heterogeneous element types
and provide traversal, conversion and named-value equality.

* tuple.1 Tuple.new returns its arguments as a tuple. first and last panic on an
  empty tuple; their ? forms return nil. empty? reports whether there are no
  elements. (test/cli/std_tuple_exercise.iyi)
* tuple.2 each and each_with_index visit tuple members in order. map preserves
  arity while replacing each value, concatenation appends the other tuple, and
  reverse reverses member order, including for empty tuples.
  (test/cli/std_tuple_exercise.iyi)
* tuple.3 to_a copies tuple members into a caller-tape Array whose element type
  is their union; an empty tuple produces Array(NoReturn). These are slot
  copies, subject to SPEC 1.4. (test/cli/std_tuple_exercise.iyi)
* tuple.4 NamedTuple size, keys, values and iteration use declaration order.
  has_key? compares key symbols and supports quoted keys.
  (test/cli/std_tuple_exercise.iyi)
* tuple.5 NamedTuple equality compares the key set and corresponding values
  regardless of declaration order. Equal values hash alike in sorted key order.
  same? uses value equality. (test/cli/std_tuple_exercise.iyi)
* tuple.6 NamedTuple printing writes brace-delimited key/value pairs in
  declaration order with inspected values. Keys outside the ASCII identifier
  set, digit-leading keys, empty keys and underscore are quoted; inspect is the
  same text. Built text follows SPEC 1.5. (test/cli/std_tuple_exercise.iyi)

## udp

UdpSocket sends and receives RFC 768 datagrams with explicit payload
bounds and numeric IPv4 or IPv6 endpoints.

* udp.1 Factories create unbound clients or bind numeric interfaces and
  localhost; port zero chooses an ephemeral port. bind? returns SocketError on
  bind failure, while bind panics. Binding does not enable address reuse.
  (test/cli/std_udp_exercise.iyi)
* udp.2 send_to sends one borrowed String or byte buffer as one datagram and
  returns its count. connect sets the default peer; send uses it. Hostname
  lookup is not provided, and invalid addresses, ports, negative counts or
  closed sockets panic. (test/cli/std_udp_exercise.iyi)
* udp.3 receive_from returns payload, sender address and sender port, or writes
  payload into the caller's Array and returns its count. receive_datagram wraps
  the same information, and receive returns only payload. Results use the
  receiver's tape under SPEC 1.5. (test/cli/std_udp_exercise.iyi)
* udp.4 A datagram larger than the requested capacity is truncated to that
  capacity and its remainder discarded. A zero-length datagram is a successful
  receive, distinct from nil returned by nonblocking forms.
  (test/cli/std_udp_exercise.iyi)
* udp.5 Blocking receives park when no datagram is queued and return Cancelled
  when cancelled or closed during a wait. Question-mark receives never park and
  return nil when nothing is ready, including on an unbound socket. There are no
  receive timeout settings. (test/cli/std_udp_exercise.iyi)
* udp.6 poll_read reports readability within its millisecond bound. Receive and
  send buffer size accessors use the platform socket options. Local address and
  port describe the current binding. (test/cli/std_udp_exercise.iyi)
* udp.7 close is idempotent and explicitly releases the descriptor. Datagram
  text and to_s alias payload bytes; tuple conversion orders data, host, port
  and indexed access rejects indices outside 0..2. Resource use obeys SPEC 5.1.
  (test/cli/std_udp_exercise.iyi)

## unicode

Unicode exposes Unicode 17.0.0 character properties, case mapping,
UTF conversion, normalization and extended grapheme segmentation.

* unicode.1 Character predicates use the generated UCD categories: letter L,
  number N, mark M, lowercase Ll, uppercase Lu and titlecase Lt. whitespace?
  means Zs, Zl or Zp; control? includes Cc, Cf, Cs and Co. ascii? means code
  points below 128. (test/cli/std_unicode_exercise.iyi)
* unicode.2 general_category and script return the UCD names, including Cn and
  Unknown for unassigned entries. property_ranges returns sorted inclusive
  endpoint pairs as a flat Array for exact category, major category or script
  names, or nil for unknown properties. (test/cli/std_unicode_exercise.iyi)
* unicode.3 Char case operations without a block use simple one-character
  mappings; block forms yield full mappings. ASCII options restrict changes to
  ASCII and Turkic options apply dotted and dotless I rules. Downcase Fold uses
  case folding. (test/cli/std_unicode_exercise.iyi)
* unicode.4 String casing uses full mappings; downcase handles final sigma and
  context-sensitive Turkic dots. capitalize titlecases the first character and
  lowers the rest. case_orbit and each_case_orbit expose simple-fold equivalence
  classes. (test/cli/std_unicode_exercise.iyi)
* unicode.5 valid? checks UTF-8 including overlong sequences, surrogate
  encodings, truncation and the U+10FFFF bound. clean preserves valid bytes and
  replaces each maximal malformed subpart with U+FFFD, returning the input view
  when it is already valid. (test/cli/std_unicode_exercise.iyi)
* unicode.6 Case mapping, UTF-16 encoding and normalization panic on malformed
  UTF-8 with its byte offset. UTF-16 decoding combines surrogate pairs; an
  unpaired surrogate returns nil from decode_utf16? and panics with its index
  from decode_utf16. (test/cli/std_unicode_exercise.iyi)
* unicode.7 Normalization supports NFD, NFC, NFKD and NFKC, defaulting to NFC,
  with canonical combining order and algorithmic Hangul composition and
  decomposition. normalized? compares the normalized result with the input.
  (test/cli/std_unicode_exercise.iyi)
* unicode.8 Grapheme operations implement UAX #29 extended clusters, including
  Indic conjuncts, regional-indicator pairs and emoji joins. Each malformed
  UTF-8 part is treated separately; String exposes the same graphemes,
  each_grapheme and grapheme_size operations.
  (test/cli/std_unicode_exercise.iyi)
* unicode.9 Grapheme Strings view the input, and property, orbit and UTF-16
  arrays use the caller's tape. Transformations build caller-tape text under
  SPEC 1.5, with unchanged ASCII normalization and valid clean allowed to return
  borrowed text. Retention follows SPEC 1.7.
  <!-- todo: Needs proof -->

## uri

URI parses, writes, normalizes and resolves RFC 3986 references;
Params handles ordered form-encoded query pairs.

* uri.1 parse returns ParsedURI with component views of its input; parse?
  returns nil for invalid references while parse panics with a reason. Empty
  input is a valid relative reference. Converting to URI wraps the parsed
  components; retaining borrows follows SPEC 1.7. (src/std/uri.iyi)
* uri.2 Parsing rejects spaces and controls, invalid schemes, malformed host
  delimiters and hosts, repeated @, nondecimal ports and ports above 65535.
  Userinfo escapes are validated; path, query and fragment escapes and the
  structure inside bracketed hosts are not validated. Non-ASCII bytes pass
  through. (test/cli/std_uri_exercise.iyi)
* uri.3 Serialization preserves the component spellings, including escaped
  userinfo. User and password getters decode escapes without turning plus into
  space; setters encode supplied text. hostname removes IPv6 brackets;
  ascii_host converts international names through IDNA or returns IdnaError.
  (test/cli/std_uri_exercise.iyi)
* uri.4 Serialization prefixes a relative path whose first segment contains a
  colon with ./ so it cannot be parsed as a scheme. Builder overloads append
  without replacing existing text; new text follows SPEC 1.5.
  (test/cli/std_uri_exercise.iyi)
* uri.5 Resolution applies RFC 3986 section 5.2, including authority, query and
  fragment inheritance and dot-segment removal. Normalization returns a new
  reference with lowercase scheme and host, uppercase host escape digits,
  default ports removed and dot segments removed. (src/std/uri.iyi)
* uri.6 Default ports are supplied for recognized schemes only. Equality
  compares components as represented rather than semantic equivalence after
  normalization, and equal URI values hash alike. dup copies component
  references rather than deep-copying their bytes.
  (test/cli/std_uri_exercise.iyi)
* uri.7 Encoders preserve unreserved bytes and encode other bytes as uppercase
  %HH. encode additionally preserves reserved bytes, encode_path preserves
  slash, and encode_userinfo preserves subdelimiters; segment and form encoding
  preserve no other bytes. Percent is always encoded. (src/std/uri.iyi)
* uri.8 Optional space-to-plus encoding also escapes literal plus. Decoders
  reverse percent escapes and optionally map plus to space. Invalid escapes
  panic or return nil with question-mark forms; a builder decode? validates
  first and appends nothing on failure. (src/std/uri.iyi)
* uri.9 Params preserves pair order and duplicates. Lookup returns the first
  value or panics on a missing key; []? returns nil and fetch_all collects every
  matching value. Assignment replaces all occurrences at the first matching
  position; delete removes all and returns their values or nil.
  (test/cli/std_uri_exercise.iyi)
* uri.10 Params parsing drops one leading question mark, splits
  ampersand-separated pairs at their first equals, and treats missing equals as
  an empty value. It decodes form escapes leniently, preserving malformed
  percent text. Writing form-encodes every pair with equals, including empty
  values. (src/std/uri.iyi)
* uri.11 Params stores borrowed keys and values, and construction from arrays
  aliases those arrays. Newly parsed containers and encoded text follow SPEC
  1.5; caller-supplied text must outlive stored views under SPEC 3.2.
  <!-- todo: Needs proof -->

## user

User and Group query local accounts and parse passwd and group
records, including the current process identity.

* user.1 User carries name, decimal user and primary-group IDs, full_name, home
  and shell on supported POSIX platforms. full_name is GECOS through the first
  comma. Group carries name, decimal ID and listed member names.
  (test/cli/std_user_exercise.iyi)
* user.2 Linux lookups reread /etc/passwd and /etc/group without NSS, LDAP or
  other external account sources. Darwin uses reentrant system account lookups.
  Missing accounts and malformed lookup IDs return nil; a name containing NUL is
  not looked up. (test/cli/std_user_exercise.iyi)
* user.3 Parsing trims line ends and skips blank lines, comments, empty or
  NIS-compat names, short records and invalid numeric IDs. IDs accept unsigned
  decimal only through UInt32::MAX and are returned canonically. Lookup returns
  the first match; parse returns all valid records in order.
  (test/cli/std_user_exercise.iyi)
* user.4 User parsing requires seven fields and treats any remaining
  colon-separated text as part of shell. Group parsing requires four fields and
  splits member text at commas. Numeric lookup compares the number, including
  leading-zero spellings. (test/cli/std_user_exercise.iyi)
* user.5 current uses the real UID, not the effective UID. If no account exists,
  it uses the kernel UID and GID, USER for the name and HOME for home, with
  empty full name and shell. Missing or empty USER in that fallback panics
  naming the UID. (test/cli/std_user_exercise.iyi)
* user.6 group_ids includes the primary group first, followed by groups listing
  the name, each ID once. The explicit groups overload uses supplied order;
  Linux uses group-file order and Darwin the system group listing.
  (test/cli/std_user_exercise.iyi)
* user.7 Parsed records may borrow slices of their source text while canonical
  IDs and collections are caller-tape results under SPEC 1.5. System lookups
  copy platform-buffer text before returning. Explicit retention follows SPEC
  1.7; platform handles are released internally.
  <!-- todo: Needs proof -->

## uuid

UUID reads, writes and generates 128-bit identifiers using RFC 9562
versions 4 and 7.

* uuid.1 Construction requires exactly sixteen bytes. A String is borrowed; an
  Array view is copied into new caller-tape bytes. Results and explicit
  retention follow SPEC 1.5 and 1.7. (test/cli/std_uuid_exercise.iyi)
* uuid.2 Parsing accepts 32 hexadecimal digits or the 36-character form with
  hyphens only at positions 8, 13, 18 and 23, counting from zero. Hexadecimal
  case is ignored; invalid length, hyphens or digits panic.
  (test/cli/std_uuid_exercise.iyi)
* uuid.3 Formatting writes lowercase hexadecimal in the 8-4-4-4-12 form. write
  appends to the caller's builder; to_s and to_tape build caller-tape text.
  (test/cli/std_uuid_exercise.iyi)
* uuid.4 v4 uses operating-system secure randomness and sets version 4 and the
  RFC variant bits. version reads the high nibble of byte six; parsing does not
  require a particular version or variant. (test/cli/std_uuid_exercise.iyi)
* uuid.5 v7 writes a 48-bit Unix millisecond stamp, a 12-bit counter and 62
  fresh secure random bits. The counter advances within the same or an earlier
  millisecond; overflow advances the logical stamp. Successive calls in one
  sequential process sort increasingly as bytes and text.
  (test/cli/std_uuid_exercise.iyi)
* uuid.6 Equality compares all sixteen bytes and hashing uses those same bytes,
  independent of textual case or hyphens. (test/cli/std_uuid_exercise.iyi)

## weak_ref

WeakRef is a legacy collector-dependent interface whose lifetime
contract is unfinished for ris tapes.

* weak_ref.1 WeakRef accepts class references only; instantiating it for a value
  type is a compile error naming a class as the replacement.
  <!-- todo: Needs proof -->
* weak_ref.2 A weak reference must not expose a target after its owner has
  released it, and reading a live target must obey SPEC 3.2.
  <!-- todo: The implementation uses IyiWeak collector cells and raw
  addresses; it has no tape-owner invalidation contract (SPEC 7.1). -->
  <!-- todo: Needs proof -->
* weak_ref.3 value returns the target or nil when cleared. Inspection
  distinguishes a cleared reference from one holding a target.
  <!-- todo: Clearing is described only in collector terms; the module describes
  gc_none as never clearing a target. -->
  <!-- todo: Needs proof -->

## websocket

WebSocket implements RFC 6455 handshakes and message framing over
HTTP, with RFC 7692 permessage-deflate.

* websocket.1 Server upgrade requires HTTP/1.1 GET, Upgrade websocket,
  Connection upgrade, version 13 and a base64 key decoding to sixteen bytes.
  Invalid handshakes get 400; another version gets 426 and
  Sec-WebSocket-Version: 13. No Origin policy is applied.
  (test/cli/std_websocket_exercise.iyi)
* websocket.2 The server chooses the first protocol in its own preference list
  that the client offered. Client connection validates the 101 response, accept
  hash, protocol selection and extensions; refused protocol details return
  WebSocketError. ws and wss use HTTP upgrade, including its optional CONNECT
  proxy. (test/cli/std_websocket_exercise.iyi)
* websocket.3 serve owns the upgraded transport until its block ends and closes
  it, sending normal closure if needed. The client explicitly closes its
  connection. Closing the listener does not close upgraded connections.
  Resources obey SPEC 5.1. (test/cli/std_websocket_exercise.iyi)
* websocket.4 send and send_binary each write one whole message frame; ping
  writes a control frame. Client frames use fresh secure random masks; server
  frames are unmasked. Concurrent writes serialize whole frames.
  (test/cli/std_websocket_exercise.iyi)
* websocket.5 receive reassembles fragments into whole Messages, answers pings
  with pongs and ignores pongs. Message data is byte text on the caller's tape
  under SPEC 1.5; retained data follows SPEC 1.7.
  (test/cli/std_websocket_exercise.iyi)
* websocket.6 Invalid masking, reserved opcodes or bits, bad fragmentation,
  oversized or fragmented control frames and invalid close payload shapes fail
  with code 1002. Invalid text or close-reason UTF-8 fails with 1007, including
  incomplete final characters. (test/cli/std_websocket_exercise.iyi)
* websocket.7 max_message defaults to 16 MiB. Declared wire sizes are checked
  before allocation or payload reads and inflated output is bounded too; excess
  fails with 1009. Transport failure or EOF without close closes the connection
  and records abnormal closure 1006. (test/cli/std_websocket_exercise.iyi)
* websocket.8 permessage-deflate is offered by default and may be disabled. Only
  its four RFC 7692 parameters are accepted, with window bits 8..15 and no
  duplicate parameters. Malformed server offers are declined or rejected as
  malformed syntax; invalid client-side agreements fail.
  (test/cli/std_websocket_exercise.iyi)
* websocket.9 Agreed compression applies to text and binary messages, never
  control frames. Context persists unless the applicable no_context_takeover was
  agreed. Outgoing compression level defaults to one and must be 0..9;
  sync-flush trailers are omitted and restored when decoding.
  (test/cli/std_websocket_exercise.iyi)
* websocket.10 Caller-supplied invalid UTF-8 text, ping bodies beyond 125 bytes,
  close reasons beyond 123 bytes, invalid endpoint close codes, invalid protocol
  tokens and reserved handshake headers panic before writing.
  (test/cli/std_websocket_exercise.iyi)
* websocket.11 close sends a close and waits at most ten seconds for the peer. A
  peer-initiated close is acknowledged; receive returns nil after closure.
  close_code and close_reason report its payload, with 1005 for no code.
  Protocol failures return WebSocketError and close the transport.
  (test/cli/std_websocket_exercise.iyi)
* websocket.12 frame builds or appends wire bytes, choosing the short, 16-bit or
  64-bit payload length form and applying the optional supplied mask key.
  (src/std/websocket.iyi)
* websocket.13 Received frame lengths must use the shortest encoding allowed
  by RFC 6455 section 5.2; longer encodings fail with code 1002.
  <!-- todo: The receiver reads 16-bit and 64-bit lengths without checking
  their minimum value. Needs proof. -->
  <!-- todo: Needs proof -->

## x509

X509 reads DER and PEM certificates and verifies bounded RFC 5280
chains. It also writes signed requests and self-signed certificates.

* x509.1 Certificate parsing returns Certificate or X509Error and reads version,
  serial, issuer, subject, validity, public key, signature and recognized
  extensions. Signed and outer signature algorithms must agree. Repeated
  extensions fail. (test/cli/std_x509_exercise.iyi)
* x509.2 Recognized validation extensions include basicConstraints, keyUsage,
  extendedKeyUsage, subjectAltName, nameConstraints and key identifiers. Unknown
  critical extensions are retained and cause verification to refuse the
  certificate. TLS Feature and OCSP no-check data are exposed without performing
  revocation checks. (test/cli/std_x509_exercise.iyi)
* x509.3 verify returns a leaf-first chain to a supplied root or X509Error.
  Issuer and subject DER match byte for byte, and alternative candidate issuers
  are tried. A chain holds at most ten certificates and one search performs at
  most 100 signature checks. (test/cli/std_x509_exercise.iyi)
* x509.4 Leaf and issuers must be valid at the supplied time. The leaf must not
  be a CA and must allow serverAuth by default or clientAuth when requested.
  Issuers must be CAs, allow keyCertSign when keyUsage is present, satisfy
  pathLenConstraint and allow the requested extended purpose.
  (test/cli/std_x509_exercise.iyi)
* x509.5 DNS and IP name constraints apply to leaf names. Unsupported constraint
  kinds and malformed names or constraints fail closed. DNS matching ignores
  case and a final dot; constrained names cannot contain empty labels.
  (test/cli/std_x509_exercise.iyi)
* x509.6 Hostname verification uses subjectAltName only, never Common Name. A
  wildcard is the entire leftmost label and matches exactly one label; IP
  literals match iPAddress entries. Unicode hosts use IDNA conversion.
  (test/cli/std_x509_exercise.iyi)
* x509.7 Signatures support RSA PKCS #1 v1.5 and PSS and ECDSA with SHA-256,
  SHA-384 or SHA-512, and Ed25519 with absent parameters under RFC 8410. SHA-1
  is refused. Every RSA key in a verified chain must be at least 2048 bits; a
  trusted root's own signature is not checked. (test/cli/std_x509_exercise.iyi)
* x509.8 PEM reading selects the requested label and checks base64 before
  decoding. RisCertificateStore.read_pem clears existing certificates, copies
  parsed payloads into owned buffers and leaves an empty store if any
  certificate fails. Clearing invalidates views under SPEC 3.3.
  (test/cli/std_x509_exercise.iyi)
* x509.9 SigningKey supports Ed25519, P-256, P-384 and RSA keys, including PEM
  input. request writes PKCS #10 with a subject CN when the first name fits and
  SAN DNS names in extensionRequest. A first name beyond 64 characters is
  omitted from the request subject. (test/cli/std_acme_exercise.iyi)
* x509.10 self_signed writes a version-three certificate with supplied names and
  extensions. The Common Name is at most 64 characters; serials are positive and
  at most twenty octets. Default serials use secure randomness. No CA extensions
  are invented. (test/cli/std_acme_exercise.iyi)
* x509.11 Output uses shortest DER and signs with Ed25519, ECDSA SHA-256 or
  SHA-384, or RSA SHA-256 PKCS #1 v1.5 according to the key. Requests and
  certificates are caller-tape byte arrays under SPEC 1.5; signature_error
  exposes the same signature checks separately. (test/cli/std_acme_exercise.iyi)
* x509.12 Parsed certificates and verified chain elements may retain views into
  their DER and key data. Verification returns a new list without independently
  owning every payload. Retention requires SPEC 1.7 or a certificate store.
  Trust-store discovery and network revocation fetching are outside this module.
  <!-- todo: Needs proof -->

## xml

XML parses well-formed XML 1.0 into a caller-tape tree and serializes
it. RisXPath supplies a restricted XPath 1.0 path language.

* xml.1 parse returns the document TapeNode of an XmlTree; parse? returns nil
  instead of a parse panic. The tree stores nodes in an array, attributes and
  namespaces in indexed storage and copied text in its own builder. Node values
  are views of that owner and equality means the same tree and index.
  (src/std/xml.iyi)
* xml.2 Parsing supports declarations, comments, processing instructions,
  elements, namespaces, text, CDATA, references and an internal DTD subset. It
  requires one root, matching closing tags, quoted attributes, valid XML names
  and no duplicate attributes, including duplicates by expanded namespace name.
  <!-- todo: Needs proof: test/cli/std_xml_exercise.iyi still imports removed
  Document, Node, Parser and full XPath APIs. -->
  <!-- todo: Needs proof -->
* xml.3 Input is UTF-8 or declared US-ASCII only. Invalid UTF-8 and non-XML
  characters fail. CRLF and CR normalize to LF; literal attribute tabs and
  newlines become spaces. Non-CDATA declared attributes additionally trim and
  collapse spaces. Other encodings are unsupported.
  <!-- todo: Needs proof -->
* xml.4 Namespace prefixes must be declared, except xml which has its fixed
  namespace. Reserved xml and xmlns names and URIs cannot be rebound illegally,
  and qualified names require valid prefix and local parts.
  <!-- todo: Needs proof -->
* xml.5 DTD element, attribute-list and notation declarations are checked
  syntactically without validating content. Attribute defaults are applied.
  Internal text entities and the five predefined entities expand; external
  subsets, external entities, parameter entities and markup-bearing replacement
  text are unsupported.
  <!-- todo: Needs proof -->
* xml.6 Entity expansion defaults to at most 1000 references, ten levels deep
  and copied expansion bytes bounded by the larger of 8 MiB or 100 times input
  size. Element nesting defaults to 256. Exceeding limits refuses the document
  with a location.
  <!-- todo: Needs proof -->
* xml.7 unescape decodes valid predefined and numeric references and panics on
  unknown, unfinished or invalid references; unescape? returns nil. escape and
  escape_attribute emit the necessary character references, with optional
  ASCII-only output and builder overloads. (src/std/xml.iyi)
* xml.8 Navigation returns child, element-child, sibling, parent and root views.
  Searches compare element names and expose the first or every match. Attribute
  lookup uses exact spelling; prefix, local_name and namespace_uri expose
  qualified-name information. Text accumulation includes descendant text and
  CDATA. (src/std/xml.iyi)
* xml.9 New nodes belong to their named tree before attachment. Element and
  processing-instruction names must be valid; the processing-instruction target
  xml, ?> in its content, -- inside comments and comments ending in dash are
  refused. Added text, names, namespaces and attribute values are copied into
  tree storage. (src/std/xml.iyi)
* xml.10 Appending must reject cross-tree nodes, document nodes,
  already-parented nodes and any ancestor cycle.
  <!-- todo: append checks parent only when next_sibling is also set,
  accepting an already-parented last child; it does not reject self or
  ancestor attachment. -->
  <!-- todo: Needs proof -->
* xml.11 set_attribute replaces the named attribute or adds one, preserving
  stored text on the tree. Tree mutation and keeping views obey SPEC 3.3;
  copy_to copies the whole referenced tree according to SPEC 1.7.
  (src/std/xml.iyi)
* xml.12 Serialization escapes text and attributes, splits CDATA containing ]]>
  and preserves CR with references. It writes namespace declarations before
  attributes, empty elements as self-closing tags, and newlines after
  declaration and top-level nodes. ASCII mode uses character references for
  non-ASCII text. The DTD is omitted and expanded entities serialize as text.
  (src/std/xml.iyi)
* xml.13 RisXPath supports absolute and relative paths, //, names, *, . and ..,
  positional [n], [last()], attribute existence and equality predicates, and
  final text() or attribute selection. Full axes, arithmetic, unions and other
  functions are not supported; invalid syntax returns a reason or panics through
  parse_checked.
  <!-- todo: Needs proof -->
* xml.14 XPath node results are unique tree views in traversal order; an
  attribute-final path returns the owning elements. values returns matching
  attribute values or accumulated text. Caller-supplied lists and builders
  receive appended results; new arrays and text follow SPEC 1.5.
  <!-- todo: Needs proof -->
* xml.15 Declaration version, encoding and optional standalone are shared by
  every node in a tree. Their setters update the document declaration; text
  setters copy into tree storage. UTF-8 is the normal serialization encoding,
  with US-ASCII selecting reference output.
  <!-- todo: Needs proof -->

## xz

Xz and XzReader decompress the XZ file format 1.0.4 and legacy
LZMA_Alone streams, including concatenated XZ streams.

* xz.1 XZ decoding checks header and block CRCs, padding, declared sizes, block
  checks, index records and footer consistency. Supported checks are none,
  CRC32, CRC64 and SHA-256; reserved check types are refused rather than
  ignored. (test/cli/std_xz_exercise.iyi)
* xz.2 XZ streams may be concatenated with zero padding in multiples of four
  bytes. Trailing bytes that are neither padding nor another stream return
  XzError. LZMA_Alone reads one 13-byte-header stream ending at its declared
  size or end marker and refuses trailing bytes. (test/cli/std_xz_exercise.iyi)
* xz.3 Filter chains support final LZMA2 with preceding delta and x86 BCJ
  filters, including the x86 start offset. Other BCJ filters and unsupported
  chains return named XzError values. Compression, parallel block decoding and
  index seeking are not supplied. (test/cli/std_xz_exercise.iyi)
* xz.4 The default dictionary limit is 64 MiB. Caller limits must be 4 KiB..1.5
  GiB; otherwise construction panics. A stream requesting more than the limit
  fails before allocating its dictionary. Dictionary storage grows from at most
  64 KiB as needed. (test/cli/std_xz_exercise.iyi)
* xz.5 read returns at most max bytes, may return short before EOF, and returns
  empty only after successful completion. Nonpositive max panics. Corruption,
  truncation or inconsistent sizes returns XzError and later reads return the
  same error. Checks can fail after earlier bytes have already been delivered.
  (test/cli/std_xz_exercise.iyi)
* xz.6 Reader input is head followed by the borrowed IO, which is read through
  EOF for XZ concatenation and never closed here. Whole decompression and read
  results are copied into caller-tape Strings under SPEC 1.5; working buffers
  belong to the reader. finished? requires checked completion and all output
  consumed. (test/cli/std_xz_exercise.iyi)

## yaml

YAML reads and writes a YAML 1.2.2 core-schema subset with typed
conversion, anchors, aliases and merge keys.

* yaml.1 parse_all reads every document; parse returns the first only after
  checking the whole stream, or a null TapeValue for an empty stream. Invalid
  input panics with a located sentence; question-mark forms return nil.
  Directives are skipped and document markers delimit streams.
  (test/cli/std_yaml_exercise.iyi)
* yaml.2 Block and flow mappings and sequences support indentation nesting,
  inline collection nesting and trailing flow commas. Scalars support plain
  folding, single-quoted doubling, double-quoted YAML escapes and literal or
  folded block styles with indentation and chomping indicators.
  (test/cli/std_yaml_exercise.iyi)
* yaml.3 Plain scalars resolve under the 1.2 core schema: null and booleans,
  decimal, 0o and 0x integers, decimal floats, infinities and NaN. Integers
  beyond Int64 become Float64. yes, no, on, off, timestamps and
  underscore-separated numbers remain Strings; leading-zero integers remain
  decimal. (test/cli/std_yaml_exercise.iyi)
* yaml.4 Keys use the same scalar resolution as values. Duplicate keys fail;
  collection keys and explicit question-mark keys are unsupported. Only core
  str, int, float, bool, null, seq and map tags and their full verbatim
  spellings are accepted. (test/cli/std_yaml_exercise.iyi)
* yaml.5 Aliases require an already completed anchor and cannot form cycles.
  Merges accept mappings or sequences of mappings; explicit keys override merged
  ones and the first merged occurrence wins. A repeated merge key fails. Anchors
  do not cross documents. (test/cli/std_yaml_exercise.iyi)
* yaml.6 Nesting is limited to 100 levels, including depth reached through
  aliases and merges. Aliases may expand at most 1000000 nodes per stream.
  Exceeding either bound fails before an unsafe value is returned.
  (test/cli/std_yaml_exercise.iyi)
* yaml.7 UTF-16 input, tabs in indentation, forbidden control or noncharacter
  code points, surrogate escapes, unknown tags, invalid indentation, trailing
  node text and unclosed strings or collections are refused. Anchors or aliases
  on block mapping keys are unsupported. (test/cli/std_yaml_exercise.iyi)
* yaml.8 TapeValue holds null, Bool, Int64, Float64, String, a pool-backed
  sequence or mapping. Checked casts panic on wrong kinds; nilable casts return
  nil. Float reads widen integers. Indexing and dig support negative array
  positions and nilable traversal; String size is its byte length.
  (test/cli/std_yaml_exercise.iyi)
* yaml.9 Value equality compares structure and kind and agrees with hashing.
  Mapping lookup uses scalar keys; inspection recursively displays values. A
  missing key or index panics in checked forms and returns nil in question-mark
  forms. (test/cli/std_yaml_exercise.iyi)
* yaml.10 dump writes block YAML preserving supported scalar and collection
  kinds, quotes Strings that could resolve differently in YAML 1.2 or common
  YAML 1.1 readers, and escapes forbidden raw characters. Collections cannot be
  emitted as keys. Builder forms append; String results follow SPEC 1.5.
  (test/cli/std_yaml_exercise.iyi)
* yaml.11 Typed conversion handles supported scalars, arrays, hashes, TapeValue,
  nilable values and ToYAML types, rejecting incompatible kinds and integer
  bounds. Derived types map fields in declaration order, ignore unknown keys,
  preserve applicable defaults and reject missing required nonnil fields.
  (test/cli/std_yaml_exercise.iyi)
* yaml.12 Parser results view caller-destination pools and retained input or
  decoded text; collection values are not general-heap objects. to_any may use a
  caller-supplied pool. Retaining a document independently uses SPEC 1.7.
  (src/std/yaml.iyi)

## zip

ZipReader and ZipWriter read and write ZIP archives using PKWARE
APPNOTE 6.3.10, including ZIP64.

* zip.1 load locates the end record by a bounded backward scan, preferring a
  comment ending exactly at EOF, and reads entries from the central directory. A
  String source is borrowed; an IO source must support seeking and remains
  caller-owned. (test/cli/std_zip_exercise.iyi)
* zip.2 Entries expose name, sizes, method, CRC-32, flags and DOS modification
  time, interpreted as a UTC wall clock with two-second precision. Names use
  UTF-8 when flagged, otherwise CP437; a matching Unicode Path extra field
  overrides the legacy name. ZIP64 fields supply overflowing sizes and offsets.
  (test/cli/std_zip_exercise.iyi)
* zip.3 Missing end records, invalid directory bounds, split archives and
  overlapping entry spans return ZipError. The reader's total uncompressed-size
  limit is checked from the directory before content is decoded.
  (test/cli/std_zip_exercise.iyi)
* zip.4 ZipEntryReader.open validates the local header and rejects encryption
  and unsupported methods. Reading supports stored, DEFLATE, bzip2, ZIP LZMA, xz
  and Zstandard, methods 0, 8, 12, 14, 95 and 93 respectively.
  (test/cli/std_zip_exercise.iyi)
* zip.5 Entry reads return at most max bytes, empty at checked completion, or
  ZipError. Nonpositive max panics. CRC-32 and uncompressed length are checked
  before the last piece is returned; output past the declared size fails
  immediately. A present data descriptor must repeat the directory CRC.
  (test/cli/std_zip_exercise.iyi)
* zip.6 A failed entry reader retains its error. Whole-entry read refuses sizes
  exceeding 2147483647 bytes and names streaming reads as the alternative.
  Output Strings follow SPEC 1.5; entry metadata views reader-owned text, so
  keeping it across reload obeys SPEC 3.3. (test/cli/std_zip_exercise.iyi)
* zip.7 Extraction checks every entry name before writing: empty or absolute
  names, .. components, backslashes and colons are refused. It creates
  directories, writes other entries as files and deletes a file whose content
  check fails. Unix permissions and symlink restoration are not supplied.
  (test/cli/std_zip_exercise.iyi)
* zip.8 Extraction must not follow an existing symbolic link outside the
  destination.
  <!-- todo: extract checks archive names only, then mkdir_p and File.open may
  follow existing directory or file symlinks. -->
  <!-- todo: Needs proof -->
* zip.9 String entries may be stored, deflated, bzip2-compressed or
  Zstandard-compressed. Stream entries support stored and deflated data with a
  following descriptor, borrowing the source without closing it. Directories end
  in a slash; non-ASCII names set the UTF-8 flag.
  (test/cli/std_zip_exercise.iyi)
* zip.10 ZIP64 is emitted where sizes, counts or offsets require it, or for all
  entries when explicitly requested. finish writes the central directory, end
  record and bounded comment, flushes but does not close the sink. Adding after
  finish or finishing twice panics. (test/cli/std_zip_exercise.iyi)
* zip.11 Writing encryption, LZMA, xz, split archives, extended timestamps and
  append mode is not supported. Self-extracting prefixes require offsets
  measured from the actual file start. (test/cli/std_zip_exercise.iyi)

## zstd

Zstd compresses and decompresses RFC 8878 frames; ZstdReader exposes
incremental decompressed bytes without linking libzstd.

* zstd.1 Decoding accepts concatenated frames and skippable frames, raw,
  repeated-byte and compressed blocks, Huffman literals and all sequence-table
  modes. Content sizes, present XXH64 checksums, block maxima and
  backward-reference bounds are checked. (test/cli/std_zstd_exercise.iyi)
* zstd.2 A frame requesting a dictionary returns ZstdError naming its ID.
  Windows above max_window are refused before use; the default is 8 MiB,
  matching RFC 9659 HTTP limits. Caller limits outside 1 KiB..512 MiB panic.
  (test/cli/std_zstd_exercise.iyi)
* zstd.3 Reader input begins with head and continues from the borrowed IO. read
  returns at most max bytes and at most one 128 KiB block, empty at completion,
  or ZstdError. Nonpositive max panics; a failure repeats on subsequent reads.
  (test/cli/std_zstd_exercise.iyi)
* zstd.4 A reader leaves bytes beyond its last frame in leftover. Whole-string
  decompress refuses those bytes and streams with no frame. finished? means the
  decoder ended successfully and all output was consumed.
  (test/cli/std_zstd_exercise.iyi)
* zstd.5 compress writes one frame with content size and checksum, blocks at
  most 128 KiB and a window at most 1 MiB. Repeated-byte blocks use RLE; other
  data may use compressed or raw blocks. No compression-level or dictionary
  interface is provided. (test/cli/std_zstd_exercise.iyi)
* zstd.6 Input Strings are borrowed. Decoded and compressed output Strings copy
  bytes into caller-tape results under SPEC 1.5; reader window and error storage
  belong to the reader. Caller IO is not closed.
  <!-- todo: Needs proof -->

