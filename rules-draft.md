# Rules of programming — working draft

Not wired into anything yet. Being straightened out here before any of it
moves to `~/.claude/CLAUDE.md`.

## 1. What messages does this thing respond to?

OOP is sending messages. The design question for any object is "what questions
make sense to ask this thing?" — a car responds to `wheels`. Things should
respond to messages; that is the whole model.

The failure mode is procedural code dressed as objects: pass data into a
method, inspect it, branch on it. The data is dumb and the method does the
thinking from outside. Every such branch is a question the object should have
answered itself.

**Diagnostic:** the moment a primitive is passed into a method — one is enough,
it does not have to be a signature full of them — stop and ask "did I just make
a mistake? If this thing were smarter, could I just ask it the question?" This
holds for integers and other primitives, not only structs — `port.privileged?`
instead of `port < 1024` in every caller.

Asking is mandatory; the answer is not always yes. Two values put to the same
question:

- A cancellation timeout of 3000 milliseconds came back fine as it was. Nobody
  inspects it or branches on it; it is consumed, not interrogated, so there is
  no message for it to respond to.
- An angle did not. A bare double that was sometimes radians and sometimes
  degrees became an `Angle` class — `FromRadians` / `FromDegrees` to construct,
  `.Degrees` / `.Radians` / `.ToNorthBearing` to ask. The questions were already
  being asked, as conversions scattered through the callers; the class gives
  them somewhere to live, and the named constructors settle the units once at
  the boundary instead of at every use.

Claude's default leans procedural. Check for primitives in the signature before
writing the body.
