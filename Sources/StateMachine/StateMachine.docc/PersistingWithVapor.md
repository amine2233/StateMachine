# Persisting a state machine with Vapor

Store the current state in a database and rebuild the machine on the next request.

## Overview

``StateMachine/StateMachine`` is an in-memory actor: it owns a graph of ``Transition`` values and a
cursor pointing at one ``State``. The graph is static, so it never needs to be persisted — only the
cursor does, and a ``State`` is nothing but a name.

That gives a three-step request cycle:

1. read the state name from the row,
2. rebuild the machine and fire the transition,
3. write the new state name back.

This guide builds an order workflow on Vapor 4 and Fluent. The package itself has no Vapor
dependency; everything below belongs in your app.

### Describe the workflow once

Keep the states and transitions in one place so the request handlers and the migrations agree on
the vocabulary.

```swift
// Sources/App/Orders/OrderWorkflow.swift
import StateMachine

enum OrderWorkflow {

    static let pending = State("pending")
    static let paid = State("paid")
    static let shipped = State("shipped")
    static let cancelled = State("cancelled")

    static let pay = Transition("pay", from: pending, to: paid)
    static let ship = Transition("ship", from: paid, to: shipped)
    static let cancel = Transition("cancel", from: pending, to: cancelled)

    static let states = [pending, paid, shipped, cancelled]
    static let transitions = [pay, ship, cancel]

    static func state(named name: String) -> State? {
        states.first { $0.name == name }
    }

    static func transition(named name: String) -> Transition? {
        transitions.first { $0.name == name }
    }

    /// Rebuilds the workflow positioned on a state read from storage.
    static func machine(restoredFrom state: State) -> StateMachine {
        StateMachine(initialState: state, transitions: transitions)
    }
}
```

`OrderWorkflow.state(named:)` is what turns an untrusted string from the database back into a state
you can trust. Without it, a typo or a renamed state produces a machine whose
``StateMachine/StateMachine/allowedTransitions`` is empty and every call fails with
``TransitionError/notAllowed`` — a confusing way to learn that a row is corrupt.

### Store the state name

A single column holds the whole machine.

```swift
// Sources/App/Orders/Order.swift
import Fluent
import Foundation

final class Order: Model, @unchecked Sendable {
    static let schema = "orders"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "reference")
    var reference: String

    @Field(key: "state")
    var state: String

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, reference: String, state: State = OrderWorkflow.pending) {
        self.id = id
        self.reference = reference
        self.state = state.name
    }
}
```

```swift
// Sources/App/Migrations/CreateOrder.swift
import Fluent
import StateMachine

struct CreateOrder: AsyncMigration {

    func prepare(on database: any Database) async throws {
        let state = try await database.enum("order_state")
            .cases(OrderWorkflow.states.map(\.name))
            .create()

        try await database.schema(Order.schema)
            .id()
            .field("reference", .string, .required)
            .field("state", state, .required)
            .field("updated_at", .datetime)
            .unique(on: "reference")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Order.schema).delete()
        try await database.enum("order_state").delete()
    }
}
```

Deriving the enum cases from `OrderWorkflow.states` means adding a state to the workflow and
forgetting the migration is a compile-time-visible mistake rather than a runtime one. On a database
without native enums, a `.string` column plus a `CHECK` constraint does the same job.

### Rebuild, fire, save

The handler reads the row, rebuilds the machine, fires, and writes the cursor back — inside one
transaction, so the read and the write cannot interleave with another request.

```swift
// Sources/App/Orders/OrderController.swift
import Fluent
import StateMachine
import Vapor

struct OrderController: RouteCollection {

    func boot(routes: any RoutesBuilder) throws {
        let orders = routes.grouped("orders", ":orderID")
        orders.get(use: show)
        orders.post("transitions", ":transition", use: fire)
    }

    @Sendable
    func show(req: Request) async throws -> OrderStatus {
        let order = try await find(req)
        let state = try state(of: order)

        return OrderStatus(
            reference: order.reference,
            state: state.name,
            allowed: await OrderWorkflow.machine(restoredFrom: state)
                .allowedTransitions
                .map(\.name)
        )
    }

    @Sendable
    func fire(req: Request) async throws -> OrderStatus {
        let name = try req.parameters.require("transition")

        guard let transition = OrderWorkflow.transition(named: name) else {
            throw Abort(.notFound, reason: "Unknown transition '\(name)'")
        }

        return try await req.db.transaction { db in
            let order = try await find(req, on: db, lock: true)
            let machine = OrderWorkflow.machine(restoredFrom: try state(of: order))

            await observeAudit(machine, transition: transition, order: order, logger: req.logger)

            do {
                try await machine.fire(
                    transition: transition,
                    userInfo: ["reference": order.reference]
                )
            } catch TransitionError.notAllowed {
                throw Abort(.conflict, reason: "Cannot '\(name)' an order that is \(order.state)")
            } catch TransitionError.unknown {
                throw Abort(.notFound, reason: "Unknown transition '\(name)'")
            }

            order.state = await machine.currentState.name
            try await order.save(on: db)

            return OrderStatus(
                reference: order.reference,
                state: order.state,
                allowed: await machine.allowedTransitions.map(\.name)
            )
        }
    }
}

struct OrderStatus: Content {
    let reference: String
    let state: String
    let allowed: [String]
}
```

Two details carry the whole pattern:

- ``StateMachine/StateMachine/fire(transition:userInfo:)`` returns only after every observer has
  finished, so `machine.currentState` is settled by the time the row is saved.
- Nothing else is read back out of the machine. The graph in `OrderWorkflow` is the source of truth
  for what *may* happen; the column is the source of truth for what *has* happened.

### Guard the read-modify-write

The machine is rebuilt per request, so it cannot serialise anything between requests: two
simultaneous `POST /orders/:id/transitions/pay` calls will each read `pending`, each find `pay`
allowed, and each fire. The database transaction above is what makes the pair safe — the row is
locked for the duration:

```swift
private func find(
    _ req: Request,
    on db: any Database,
    lock: Bool = false
) async throws -> Order {
    let id = try req.parameters.require("orderID", as: UUID.self)
    var query = Order.query(on: db).filter(\.$id == id)

    if lock {
        query = query.withLock(.update) // SELECT … FOR UPDATE
    }

    guard let order = try await query.first() else {
        throw Abort(.notFound)
    }

    return order
}

private func state(of order: Order) throws -> State {
    guard let state = OrderWorkflow.state(named: order.state) else {
        throw Abort(.internalServerError, reason: "Order \(order.reference) holds an unknown state")
    }

    return state
}
```

If your database has no row locks, make the write itself conditional and treat a zero-row update as
a lost race:

```swift
let updated = try await Order.query(on: db)
    .filter(\.$id == id)
    .filter(\.$state == transition.from.name)   // still where we read it
    .set(\.$state, to: transition.to.name)
    .update()
```

### Record history from an observer

Observers are `@Sendable` and may be `async`, so they can capture a `Logger`, an ID, or an actor —
but not a `Request` or a `Database`. Use them for effects that are independent of the request, and
keep the persistence in the handler where the transaction is:

```swift
private func observeAudit(
    _ machine: StateMachine,
    transition: Transition,
    order: Order,
    logger: Logger
) async {
    let reference = order.reference

    await machine.on(.leaveState(transition.from)) { _ in
        logger.info("order leaving state", metadata: [
            "order": .string(reference),
            "state": .string(transition.from.name)
        ])
    }

    await machine.on(.afterTransition(transition)) { userInfo in
        logger.notice("order transitioned", metadata: [
            "order": .string(userInfo?["reference"] as? String ?? reference),
            "transition": .string(transition.name),
            "to": .string(transition.to.name)
        ])
    }
}
```

To persist an audit trail instead of logging it, append a row in the same transaction right after
the `order.save(on: db)` call — an observer is the wrong place for it, because a failed insert
there cannot roll the transition back.

### Wire it up

```swift
// Sources/App/configure.swift
public func configure(_ app: Application) async throws {
    app.databases.use(.postgres(configuration: .init(/* … */)), as: .psql)
    app.migrations.add(CreateOrder())

    try await app.autoMigrate()
    try app.register(collection: OrderController())
}
```

```console
$ curl -s localhost:8080/orders/$ID
{"reference":"A-1","state":"pending","allowed":["pay","cancel"]}

$ curl -s -X POST localhost:8080/orders/$ID/transitions/pay
{"reference":"A-1","state":"paid","allowed":["ship"]}

$ curl -s -X POST localhost:8080/orders/$ID/transitions/cancel
{"error":true,"reason":"Cannot 'cancel' an order that is paid"}
```

Restart the server between the calls and the answers do not change: the workflow lives in the
code, the position lives in the row.

## See Also

- ``StateMachine/StateMachine/currentState``
- ``StateMachine/StateMachine/allowedTransitions``
- ``LifecycleEvent``
