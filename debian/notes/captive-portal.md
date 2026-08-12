# Getting through a captive portal by hand

The offline runbook. You are in a library, there is no browser, and `curl` is
the whole toolkit. `debian/bin/portal` automates all of this — this file is
what you follow when it does not fit the portal in front of you.

Every command below was run against a portal simulation on 2026-08-11 and the
output shown is real.

## 0. Get on the network first

Associating and reaching the internet are separate problems. Finish this one
before blaming the portal.

```sh
nmcli device wifi rescan
nmcli device wifi list
nmcli device wifi connect "Library WiFi"          # open network
nmcli device wifi connect "Library WiFi" --ask    # prompts for a password
```

Confirm you actually got an address, a gateway and a DNS server:

```sh
nmcli device status
nmcli -f IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show wlan0
ip route
```

No gateway means DHCP failed — that is not a portal, that is association.

## 1. Is there a portal at all?

Ask for a URL whose correct answer is known.

```sh
curl -sS -o /dev/null -m 8 -w 'code=%{http_code}  redirect=%{redirect_url}\n' \
     http://connectivitycheck.gstatic.com/generate_204
```

```
code=204  redirect=                      <- clear, you are online
code=302  redirect=http://portal.lib/... <- portal, and that IS its URL
```

**Use http://, never https://.** A portal cannot intercept TLS without throwing
a certificate error, so an HTTPS probe fails or hangs instead of revealing the
redirect. This is the single most common way to waste twenty minutes here.

Other probes, for when one is whitelisted or cached — portals sometimes special
case the well-known ones:

```sh
curl -sS -i -m 8 http://detectportal.firefox.com/success.txt   # want: success
curl -sS -i -m 8 http://network-test.debian.org/nm  # want: NetworkManager is online
curl -sS -i -m 8 http://captive.apple.com/hotspot-detect.html  # want: Success
```

A `200` whose body is *not* what it should be is also a portal — a transparent
proxy answered in the real server's place. Do not just check the status code.

NetworkManager's own opinion, once `[connectivity]` is configured in
`/etc/NetworkManager/conf.d/10-console.conf`:

```sh
nmcli networking connectivity check      # full | portal | limited | none
```

Check whether DNS is being hijacked too:

```sh
dig +short detectportal.firefox.com
dig +short @1.1.1.1 detectportal.firefox.com    # different answer = hijacked
```

## 2. See the redirect in full

```sh
curl -sS -i -m 8 http://connectivitycheck.gstatic.com/generate_204
```

```
HTTP/1.0 302 Found
Location: http://127.0.0.1:8731/portal
```

## 3. Follow it, keeping the cookies

This is the step that decides whether anything later works. The portal hands
out a session cookie during the redirect and will reject a submission without
it.

```sh
cd /tmp
curl -sS -L -m 15 \
     -c portal.jar -b portal.jar \
     -D portal.hdr -o portal.html \
     -w 'final url: %{url_effective}\n' \
     http://connectivitycheck.gstatic.com/generate_204
```

- `-c` writes the cookie jar, `-b` reads it — use **both**, every time
- `-D` saves headers, `-o` saves the body, `-L` follows the redirect chain
- `%{url_effective}` is where you actually landed; relative form actions
  resolve against it

```sh
grep -i set-cookie portal.hdr
```

```
Set-Cookie: session=sess-abc123; Path=/
```

## 4. Read the form

```sh
sed 's/</\n</g' portal.html | grep -iE '^<(form|input|select|textarea)'
```

```
<form action="/login" method="POST">
<input type="hidden" name="csrf_token" value="csrf-9f3a21">
<input type="hidden" name="client_mac" value="a4:5e:60:11:22:33">
<input type="hidden" name="ap_mac" value="00:0c:29:aa:bb:cc">
<input type="hidden" name="redirect" value="http://example.com/">
<input type="checkbox" name="accept" value="">
<input type="submit" name="submit" value="Connect">
```

The hidden fields are the point. A POST built from the visible checkbox alone
gets rejected.

Before going further, check it is not a dead end:

```sh
printf 'forms=%s inputs=%s scripts=%s\n' \
  "$(grep -oi '<form' portal.html | wc -l)" \
  "$(grep -oi '<input' portal.html | wc -l)" \
  "$(grep -oi '<script' portal.html | wc -l)"
```

`grep -o ... | wc -l`, not `grep -c`. `-c` counts matching *lines*, and a
JavaScript portal ships its HTML minified onto one line — so `-c` reports
`scripts=1` for a page with twelve of them, and `forms=1` for a page with
three. The `forms=0` verdict survives either way, since no matching lines does
mean no matches, but every other number is wrong when it matters most.

`forms=0 scripts=12` means the page builds its request in JavaScript. **Stop —
curl cannot do this and neither can w3m.** Go to the fallbacks at the bottom.

Two things `curl -L` will not have followed:

```sh
grep -i 'http-equiv=.refresh' portal.html          # meta refresh redirect
grep -i 'WISPAccessGatewayParam\|LoginURL' portal.html   # older WISPr portals
```

## 5. Send it back

Echo every field back, changing only what needs changing. A checkbox that
arrives as `value=""` usually wants `on`.

```sh
curl -sS -m 15 -b portal.jar -c portal.jar \
  --data-urlencode 'csrf_token=csrf-9f3a21' \
  --data-urlencode 'client_mac=a4:5e:60:11:22:33' \
  --data-urlencode 'ap_mac=00:0c:29:aa:bb:cc' \
  --data-urlencode 'redirect=http://example.com/' \
  --data-urlencode 'accept=on' \
  -w '\nHTTP %{http_code}\n' \
  http://portal.lib/login
```

Forgetting the checkbox looks like this:

```
REJECTED: terms not accepted
HTTP 403
```

Getting it right looks like this:

```
CONNECTED - you may now browse
HTTP 200
```

Use `--data-urlencode`, not `-d` — MACs, URLs and tokens contain characters
that need escaping. The form's `action` was `/login`, relative, so it resolves
against the final URL from step 3.

## 6. Prove it worked

Do not trust the portal's own success page.

```sh
curl -sS -o /dev/null -m 8 -w 'code=%{http_code}\n' \
     http://connectivitycheck.gstatic.com/generate_204
```

```
code=204          <- actually online
```

```sh
nmcli networking connectivity check    # should now say: full
```

## When it does not work

**TLS errors.** Portals routinely present self-signed or mismatched
certificates. `curl -k` proceeds anyway — know that you are sending whatever
you type to an unverified host.

**The portal ignores curl.** Some serve different content, or nothing, without
a browser User-Agent:

```sh
curl -sS -A 'Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/128.0' ...
```

**It needs a real browser session.** `w3m http://portal.lib/` walks HTML forms
interactively — tab to the checkbox, Enter. Most library portals are plain
forms and this just works. `w3m` is an apt package, so it can only be installed
before the gate.

**It is JavaScript-only.** Nothing on this machine can complete it. Either:

- tether to a phone hotspot instead, or
- authorise on another device, then clone that device's MAC:

  ```sh
  nmcli connection modify "Library WiFi" 802-11-wireless.cloned-mac-address AA:BB:CC:DD:EE:FF
  nmcli connection up "Library WiFi"
  ```

  `/usr/lib/NetworkManager/conf.d/no-mac-addr-change.conf` is present, so this
  machine's MAC is stable by default — a portal that authorises by MAC will
  remember it between visits, and you may not have to do any of this twice.

## The automated version

```sh
portal                                   # detect, print the URL
portal inspect http://portal.lib/...     # dump every form field
portal submit http://portal.lib/login csrf_token=... accept=on
```

Cookies persist in `~/.cache/portal/` between those three commands. See
`debian/bin/portal`.
