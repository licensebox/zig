# Licensebox for Zig

Linux native application SDK, backed by Licensebox C v0.3.0. Requires Zig 0.14.1. Other operating systems and cross compilation have not been validated. This SDK contains no server/admin credentials or administration API.

Install the native library using `bash scripts/install-native.sh /your/prefix`, or build/install the pinned C SDK yourself. Set `LICENSEBOX_LIB_DIR=/your/prefix/lib` for building and `LD_LIBRARY_PATH=/your/prefix/lib` for running. Headers are expected in `/your/prefix/include`. `LICENSEBOX_LIBRARY` is supplied by CI for consistency; this binding links `liblicensebox.so` through the Linux loader and uses `LICENSEBOX_LIB_DIR`/`LD_LIBRARY_PATH`. Native dependencies are OpenSSL and libcurl. HTTPS verification stays enabled.

Run `bash ci/test.sh` from this repository after installing the toolchain. `ci/setup.sh` installs prerequisites on a disposable Ubuntu 24.04 CI runner. The test script runs real binding tests, builds the language conformance adapter and compiles a consumer against the installed/package surface.

## Application API

Create a client with JSON options:

```json
{"product":"your-product","keys":{"current":"YOUR_ED25519_PUBLIC_KEY"},"version":"1.0","directory":"/private/application/state","server":"https://licensebox.dev","ca_bundle":"/optional/trusted-ca.pem"}
```

Only `product` and `keys` are required. Omit optional values to use native defaults. `keys` maps signing-key IDs to unpadded base64url public keys. `ca_bundle` is optional; omit it for the system trust store. Never pass private signing keys. Do not expose trusted clock/binding callbacks as end-user configuration. Embedded NUL bytes in textual arguments fail closed.

Initialization: `try lb.Client.init(allocator, options_json, callbacks)`. Operation: `try client.call(operation, args_json)`. See [the complete example](examples/status.zig).

| Operation | JSON arguments | Result |
| --- | --- | --- |
| `lease` | `{}` | verified lease |
| `require` | `{"module":"core"}` | verified lease authorizing that module |
| `status` | `{}` | locally verified lease |
| `sign_in` | `{"timeout":120}` | verified lease |
| `logout` | `{}` | `null` |
| `modules` | `{}` | module objects |
| `requests` | `{}` | access requests |
| `request` | `{"modules":["export"],"note":"reason"}` | submitted request |
| `access-link` | `{}` | private URL string |
| `record` | `{"command":"export","success":true,"elapsed":0.125}` | `null` |

Elapsed and timeout values are seconds. Usage collection obeys the server opt-in. Check protected access before reading user files. A protected call attempts renewal; it does not start a background heartbeat. Explicit server refusals fail closed. Unexpired verified cached leases can cover eligible transport outages; expired leases require a connection. Logout preserves the installation key. Keep lease/access-link/device-code values private.

Client initialization returns `ClientResult` (`client` or `failure`); operations return `Outcome` (`value` or `failure`). Native errors preserve `.failure.code` and `.message`. `.value` contains JSON text, including JSON strings for binding/access-link results. Call `outcome.deinit(allocator)` once. Allocator errors use Zig error unions. Own a client pointer once; aliases share `close` state. `destroy` invalidates all aliases and must run once. Do not copy the client struct by value. Calls and error capture share a mutex.

The public callback record preserves context, sign-in `(context, url, user_code)`, trusted clock `(context) -> seconds`, trusted binding `(context, output, capacity) -> zero on success`, and cancellation `(context) -> nonzero when cancelled`. Retain context and every language callback until the client closes. C callbacks must never raise/unwind through C, terminate the process, or reenter a client. Leave clock/binding unset in production applications to use the native implementation. Use sign-in callbacks to display the URI and code.

Stateless primitives verify a signed lease, derive a namespaced binding from a trusted identity source, and read the native binding. They delegate to the same native implementation as client operations; parsing JSON never authorizes a feature. Raw native IDs must remain local.

## Conformance

With the shared protocol checkout at `../protocol`, run:

```sh
python3 ../protocol/conformance/run.py --adapter bash "$PWD/ci/adapter.sh"
```

All keys, host identifiers and records in tests are synthetic. The adapter executes operations in Zig. Trusted clock/binding callbacks are confined to the test adapter. The native library must be installed before testing.

## Optional protected-work checkpoints

```zig
const checkpoint = try client.heartbeat("core");
defer checkpoint.deinit(allocator);
switch (checkpoint) {
    .failure => return error.AuthorizationFailed,
    .value => {},
}
```

The result is the owned JSON value/string `{"lease":{...},"online":true|false}`
using this binding's existing JSON and cleanup conventions.

The explicit checkpoint always attempts signed renewal with a three-second
network bound, even after a cached `Require` succeeded. It never activates,
opens interactive sign-in, creates/rotates an installation key or transfers a
seat. Missing saved state returns `not_signed_in`; invalid saved state, a removed
module or explicit server refusal fails closed. Eligible outages may return a
verified unexpired saved lease with `online=false`, without extending its signed
expiry or clearing a saved refusal. A successful renewal replaces cached grants
before checking the requested nonempty module.

Use the matching native core containing the heartbeat API. Consumers own their
event loop and safe stop/pause behavior. Read the optional verified `heartbeat`
policy (`interval_seconds`, `grace_seconds`) to schedule checks; missing/null is
legacy policy. Independently stop protected work by the last verified `expires`
even when renewal is slow, and never move that deadline after a failed check.
Construction, Lease and Require start no background worker. Callback lifetime,
thread ownership and reentry requirements remain unchanged; the SDK never kills
the application or discards application results.
