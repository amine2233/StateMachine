# StateMachine

A small finite state machine for Swift, isolated by an actor.

Describe the graph once with `State` and `Transition` values, then let the machine decide what may
happen next. It holds no storage of its own — a graph plus a cursor — so persisting or restoring a
machine means persisting one string.

## Requirements

| | |
|---|---|
| Swift | 6.0 (language mode 6, strict concurrency) |
| Platforms | iOS 14 · macOS 10.15 · tvOS 14 · watchOS 7 · visionOS 1 |

## Installation

```swift
.package(url: "https://github.com/amine2233/StateMachine.git", from: "1.0.0")
```

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "StateMachine", package: "StateMachine")
])
```

## Usage

```swift
import StateMachine

let draft = State("draft")
let published = State("published")
let publish = Transition("publish", from: draft, to: published)

let machine = StateMachine(initialState: draft, transitions: [publish])

try await machine.fire(transition: publish)
await machine.currentState == published  // true
```

Firing a transition the machine does not know throws `TransitionError.unknown`; firing one that
does not start from the current state throws `TransitionError.notAllowed`. Ask first with
`canFire(transition:)` or `allowedTransitions` — the latter is what UI usually binds to, so buttons
enable themselves from the graph:

```swift
let names = await machine.allowedTransitions.map(\.name)  // ["publish"]
```

### Observing the lifecycle

One observer per `LifecycleEvent`. They run in a fixed order and `fire` only returns once they have
all finished, so the machine's state is settled by the time the call site continues:

```swift
await machine.on(.onState(published)) { userInfo in
    await index.add(userInfo?["id"] as? String)
}

try await machine.fire(transition: publish, userInfo: ["id": article.id])
```

`beforeTransition` → `leaveState` → `onState` → `onTransition` → `afterTransition`.

Observers are `@Sendable` and may be `async`, so they can only capture `Sendable` values.
Registering a second observer for the same event replaces the first.

### Restoring a machine

The graph is static; only the cursor moves. Save `currentState.name`, and pass it back as
`initialState` to carry on where you left off:

```swift
let machine = StateMachine(initialState: State(order.state), transitions: OrderWorkflow.transitions)
```

> **Note**
> SwiftUI declares its own `State` and `Transition`. In a file that imports both modules, write
> `StateMachine.State` / `StateMachine.Transition`, or keep the graph in files that do not import
> SwiftUI.

## Documentation

The [DocC documentation](https://amine2233.github.io/StateMachine/documentation/statemachine)
carries the API reference plus two complete guides:

- **Driving a SwiftUI onboarding flow** — a five-step `NavigationStack` where next, back and
  "start over" are edges in the graph, and the swipe-back gesture is replayed through the machine.
- **Persisting a state machine with Vapor** — storing the current state in a Fluent column,
  rebuilding the machine per request, and guarding the read-modify-write with a transaction.

Build them locally:

```sh
mise run build_documentations macOS --serve
```

## Development

```sh
mise run test     # swift test
mise run lint     # format + code + documentation checks
mise run format   # apply formatting
```

## License

MIT — see [LICENSE](LICENSE).
