# Zoom-out review (third review)

Target: doc/drafts/fileserver-outgoing.md

Ready from a simplicity and scope view, one Major, no Blockers.

## Review-2 Majors

* MA1 resolved: check in `format_head`, both callers named (234-269).
* MA2 resolved: values copied into the answer's text via
  `String::Span` / `append_span`; block rules listed (169-232).
* MA3 resolved: probed (P1), negative gate, compiler TODO, Outgoing
  safe whatever the checker accepts (91-140).
* MA4 resolved, but by adding scope (Major 1).
* MA5 resolved (286-308; case 18). MA6 resolved (10-37, tables).
* MA7 resolved (244-253).

## Major 1: private HTTP-date parser (401-432, 453-458, 667-668)

A three-form parser (IMF-fixdate, RFC 850, asctime) plus helpers,
built only because std/time's parser does not compile on ris, and
planned for deletion. The failure is located (P6): a scratch
`TimeParseError` stored at time.iyi:2776; fixing it fixes
`Time.parse_rfc1123` for all callers. mail.iyi:1780-1840 already
parses RFC 5322 dates, with its own `days_from_civil`
(mail.iyi:1052 vs time.iyi:1784): duplication is spreading. A7
(534-535) calls the fix "unrelated", but it is the same scratch-escape
class. Fix time.iyi:2776 first, or ship fixdate-only and record the
RFC 9110 5.6.7 gap.

## Nits

1. 205-207, 577-578, P8: the nested-header guard guards a misuse
   no caller makes; cheap, most speculative rule.
2. 246-249: refuse `length=` on any non-HEAD answer: one rule.
3. 177-183: packed `@state`, one-element `@size`; name the idiom or
   use named fields.
4. 361-386, 434-476, 641-656: full bodies and script are detail;
   cite rather than inline (style call).
5. 138-140, 230-232: copy cost unmeasured; name a regression level
   that would reopen the choice.
