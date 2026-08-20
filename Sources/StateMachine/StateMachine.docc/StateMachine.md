# ``StateMachine``

A small finite state machine, isolated by an actor.

## Overview

Describe the graph with ``State`` and ``Transition`` values, then drive it through
``StateMachine/StateMachine``. Every mutation happens on the actor, so a machine can be shared
across tasks without a lock:

```swift
import StateMachine

let draft = State("draft")
let published = State("published")
let publish = Transition("publish", from: draft, to: published)

let machine = StateMachine(initialState: draft, transitions: [publish])

try await machine.fire(transition: publish)
await machine.currentState == published // true
```

Firing a transition the machine does not know throws ``TransitionError/unknown``; firing one that
does not start from the current state throws ``TransitionError/notAllowed``. Ask before you fire
with ``StateMachine/StateMachine/canFire(transition:)`` or
``StateMachine/StateMachine/allowedTransitions``.

### Observing the lifecycle

Register one observer per ``LifecycleEvent``. They run in a fixed order —
`beforeTransition`, `leaveState`, `onState`, `onTransition`, `afterTransition` — and
``StateMachine/StateMachine/fire(transition:userInfo:)`` only returns once they have all finished:

```swift
await machine.on(.onState(published)) { userInfo in
    await index.add(userInfo?["id"] as? String)
}
```

Observers are `@Sendable` and may be `async`, so they can only capture `Sendable` values.

### Rebuilding a machine

A machine holds no storage of its own: it is a graph plus a cursor. Persist
``StateMachine/StateMachine/currentState`` — the name is enough — and rebuild the same machine
later by passing that state back as `initialState`. See <doc:PersistingWithVapor> for a complete
server-side example.

## Topics

### Essentials

- ``StateMachine/StateMachine``
- ``State``
- ``Transition``

### Observing

- ``LifecycleEvent``

### Errors

- ``TransitionError``

### Guides

- <doc:PersistingWithVapor>
