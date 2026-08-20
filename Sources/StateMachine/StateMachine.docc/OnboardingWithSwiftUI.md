# Driving a SwiftUI onboarding flow

Walk a five-step onboarding with a `NavigationStack`, where the machine decides what "next",
"back" and "start over" mean.

## Overview

An onboarding flow is a graph that happens to look like a line: five screens, forward one at a
time, back one at a time, plus a shortcut back to the very first screen. Encoding that graph in
``StateMachine/StateMachine`` instead of in the views means the buttons never have to know where
they are — they ask ``StateMachine/StateMachine/allowedTransitions`` and enable themselves.

The pieces:

- an `OnboardingStep` enum, one case per screen, each mapped to a ``State``,
- an `OnboardingFlow` that builds the ``Transition`` graph from that list,
- a `@MainActor @Observable` model that owns the machine and the `NavigationStack` path,
- views that only push, pop, and read.

### The steps

```swift
// OnboardingStep.swift
import StateMachine

enum OnboardingStep: String, CaseIterable, Identifiable, Hashable {
    case welcome
    case permissions
    case profile
    case notifications
    case ready

    var id: String { rawValue }

    var state: State { State(rawValue) }

    init?(_ state: State) {
        self.init(rawValue: state.name)
    }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .permissions: "Permissions"
        case .profile: "Your profile"
        case .notifications: "Notifications"
        case .ready: "You're ready"
        }
    }
}
```

> Important: SwiftUI declares its own `State` and `Transition`, so a file that imports both SwiftUI
> and StateMachine cannot say `State` unqualified. Keep the graph in files that do not import
> SwiftUI — as below — or write `StateMachine.State` and `StateMachine.Transition` where they meet.

### The graph

Three families of transition, all derived from the case order — adding a sixth step means adding a
case and nothing else.

```swift
// OnboardingFlow.swift
import StateMachine

enum OnboardingFlow {

    static let steps = OnboardingStep.allCases

    /// `welcome → permissions → profile → notifications → ready`
    static let forward: [Transition] = zip(steps, steps.dropFirst()).map { current, next in
        Transition("continue-to-\(next.rawValue)", from: current.state, to: next.state)
    }

    /// The same edges, reversed.
    static let backward: [Transition] = zip(steps, steps.dropFirst()).map { previous, current in
        Transition("back-to-\(previous.rawValue)", from: current.state, to: previous.state)
    }

    /// A shortcut from every step to the first one.
    static let toStart: [Transition] = steps.dropFirst().map { step in
        Transition("start-over-from-\(step.rawValue)", from: step.state, to: steps[0].state)
    }

    static let transitions = forward + backward + toStart

    static func machine(from step: OnboardingStep = .welcome) -> StateMachine {
        StateMachine(initialState: step.state, transitions: transitions)
    }

    static func forward(from step: OnboardingStep) -> Transition? {
        forward.first { $0.from == step.state }
    }

    static func backward(from step: OnboardingStep) -> Transition? {
        backward.first { $0.from == step.state }
    }

    static func toStart(from step: OnboardingStep) -> Transition? {
        toStart.first { $0.from == step.state }
    }
}
```

The three lookups are the only place a screen name meets a transition name. Everything downstream
works in ``Transition`` values.

### The model

`path` is the `NavigationStack` path *and* the only thing the views mutate. Pushes come from
`advance()`; pops come from SwiftUI itself — the swipe-back gesture and the navigation bar's back
button both shorten the array, and `didSet` replays those pops through the machine, so the state
and the stack can never drift apart.

```swift
// OnboardingModel.swift
import Observation
import StateMachine

@MainActor
@Observable
final class OnboardingModel {

    private(set) var step: OnboardingStep = .welcome
    private(set) var allowed: [Transition] = []
    private(set) var isComplete = false

    var path: [OnboardingStep] = [] {
        didSet {
            guard path.count < oldValue.count else { return }

            Task { await rewind(to: path.last ?? .welcome) }
        }
    }

    private let machine: StateMachine

    init(machine: StateMachine = OnboardingFlow.machine()) {
        self.machine = machine
    }

    var canAdvance: Bool { isAllowed(OnboardingFlow.forward(from: step)) }
    var canGoBack: Bool { isAllowed(OnboardingFlow.backward(from: step)) }
    var canStartOver: Bool { isAllowed(OnboardingFlow.toStart(from: step)) }

    var progress: Double {
        Double(OnboardingFlow.steps.firstIndex(of: step) ?? 0)
            / Double(OnboardingFlow.steps.count - 1)
    }

    func start() async {
        await machine.on(.onState(OnboardingStep.ready.state)) { [weak self] _ in
            await self?.finish()
        }

        await sync()
    }

    func advance() async {
        await fire(OnboardingFlow.forward(from: step))
    }

    func goBack() async {
        await fire(OnboardingFlow.backward(from: step))
    }

    func startOver() async {
        await fire(OnboardingFlow.toStart(from: step))
    }

    private func rewind(to target: OnboardingStep) async {
        while step != target, canGoBack {
            await fire(OnboardingFlow.backward(from: step))
        }
    }

    private func fire(_ transition: Transition?) async {
        guard let transition else { return }

        do {
            try await machine.fire(
                transition: transition,
                userInfo: ["from": step.rawValue]
            )
        } catch {
            return // `notAllowed` simply means the button was stale.
        }

        await sync()
    }

    /// Pulls the machine's cursor into the observable properties the views read.
    private func sync() async {
        let current = await machine.currentState

        step = OnboardingStep(current) ?? step
        allowed = await machine.allowedTransitions
        path = trail(upTo: step)
    }

    private func trail(upTo step: OnboardingStep) -> [OnboardingStep] {
        guard let index = OnboardingFlow.steps.firstIndex(of: step) else { return [] }

        return Array(OnboardingFlow.steps[...index].dropFirst())
    }

    private func isAllowed(_ transition: Transition?) -> Bool {
        transition.map(allowed.contains) ?? false
    }

    private func finish() {
        isComplete = true
    }
}
```

Two things make the `didSet` safe. Only shrinking assignments are replayed, so the `path = trail(…)`
inside `sync()` cannot start a loop. And `rewind(to:)` stops as soon as
``StateMachine/StateMachine/allowedTransitions`` stops offering a way back, so a pop straight to the
root — a long press on the back button — replays as one back transition per screen rather than
jumping the machine over states that may have side effects.

> Note: `@MainActor` types are implicitly `Sendable`, which is why the observer registered in
> `start()` can capture `self`. Its body hops back to the main actor because
> ``StateMachine/StateMachine/fire(transition:userInfo:)`` awaits observers.

### The views

The root view owns the model; every screen is the same view driven by its step.

```swift
// OnboardingView.swift
import SwiftUI

struct OnboardingView: View {

    @State private var model: OnboardingModel

    init(model: OnboardingModel = OnboardingModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        if model.isComplete {
            HomeView()
        } else {
            NavigationStack(path: $model.path) {
                OnboardingStepView(step: .welcome, model: model)
                    .navigationDestination(for: OnboardingStep.self) { step in
                        OnboardingStepView(step: step, model: model)
                    }
            }
            .task { await model.start() }
        }
    }
}

struct OnboardingStepView: View {

    let step: OnboardingStep
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 24) {
            ProgressView(value: model.progress)

            Text(step.title)
                .font(.largeTitle.bold())

            StepContent(step: step)

            Spacer()

            Button("Continue") {
                Task { await model.advance() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canAdvance)
        }
        .padding()
        .navigationTitle(step.title)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") {
                    Task { await model.goBack() }
                }
                .disabled(!model.canGoBack)
            }

            ToolbarItem(placement: .primaryAction) {
                Button("Start over") {
                    Task { await model.startOver() }
                }
                .disabled(!model.canStartOver)
            }
        }
    }
}
```

Neither view knows that `welcome` has no back button or that `ready` has no continue button. Both
buttons read `canGoBack` / `canAdvance`, which come from the machine, so the disabled states follow
the graph automatically. Drop the `.navigationBarBackButtonHidden()` and the system back button
works too — it shortens `path`, which the model replays as a back transition.

### Resuming where the user left off

The machine takes its starting state from the outside, so a half-finished onboarding survives a
relaunch by storing one string:

```swift
@AppStorage("onboarding.step") private var savedStep = OnboardingStep.welcome.rawValue

var body: some View {
    OnboardingView(
        model: OnboardingModel(
            machine: OnboardingFlow.machine(
                from: OnboardingStep(rawValue: savedStep) ?? .welcome
            )
        )
    )
}
```

Then persist it from the model's `sync()` — or, if you prefer the effect next to the graph, from an
observer registered per step in `start()`:

```swift
for step in OnboardingFlow.steps {
    await machine.on(.onState(step.state)) { [weak self] _ in
        await self?.remember(step)
    }
}
```

Note that this registers one observer per ``LifecycleEvent``; registering a second one for the same
event replaces the first.

## See Also

- <doc:PersistingWithVapor>
- ``StateMachine/StateMachine/allowedTransitions``
- ``LifecycleEvent``
