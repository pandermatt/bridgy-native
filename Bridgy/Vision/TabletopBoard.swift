#if os(visionOS)
import BridgyEngine
import RealityKit
import Spatial
import UIKit
import SwiftUI
import TabletopKit

/// A side of the board.
///
/// TabletopKit has a `Player` of its own — a person sitting at the table — so
/// ours needs naming explicitly wherever both modules are in scope.
typealias BoardSide = BridgyEngine.Player

/// Where every dot and every bridge sits on the physical table, in metres.
///
/// This does not re-derive the lattice. `BoardGeometry` already centres a board
/// inside a rectangle and knows where each cell and dot lands; handing it a rect
/// measured in metres rather than points means the 3D table is laid out by the
/// exact same code as the 2D board, padding and all.
struct BoardMetrics {
    let board: Board
    /// The playing surface's side length.
    let side: Double
    private let geometry: BoardGeometry

    init(board: Board, side: Double = 0.62) {
        self.board = board
        self.side = side
        self.geometry = BoardGeometry(
            board: board,
            rect: CGRect(x: 0, y: 0, width: side, height: side)
        )
    }

    /// One lattice unit, in metres. Everything else is a multiple of this.
    var unit: Double { Double(geometry.scale) }

    /// A bridge is two lattice units end to end.
    var bridgeLength: Double { unit * 2 }

    /// Reuses the 2D stroke weight so a bridge is as thick, relative to the
    /// board, as the one on the phone.
    func bridgeThickness(_ style: BoardStyle) -> Double {
        unit * Double(style.strokeLatticeWidth)
    }

    /// Derived from the lattice, NOT from `geometry.dotRadius`.
    ///
    /// That property floors at `max(1.5, …)` because it is sized in points, and
    /// this geometry is in metres — the floor would make every dot a metre and a
    /// half across. Positions are safe to reuse; the two floored sizes
    /// (`dotRadius`, `lineWidth`) are not.
    var dotRadius: Double { unit * 0.22 }

    /// The table plane is XZ with Y up, and the board is centred on the origin,
    /// so the 2D point's y becomes z and both are shifted by half the side.
    private func plane(_ point: CGPoint) -> SIMD3<Float> {
        SIMD3(Float(Double(point.x) - side / 2), 0, Float(Double(point.y) - side / 2))
    }

    func cellCentre(_ cell: Int) -> SIMD3<Float> {
        plane(geometry.center(of: board.move(at: cell)))
    }

    func dotCentre(_ dot: BoardGeometry.Dot) -> SIMD3<Float> {
        plane(geometry.point(of: dot))
    }

    /// Same place as the dot; named for what it is in the water.
    func postCentre(_ dot: BoardGeometry.Dot) -> SIMD3<Float> {
        dotCentre(dot)
    }

    func dots(for player: BoardSide) -> [BoardGeometry.Dot] {
        geometry.dots(for: player)
    }

    /// True when this player's bridge across this cell runs along z (the
    /// direction Down is trying to travel) rather than along x.
    func runsAlongZ(cell: Int, player: BoardSide) -> Bool {
        let (from, to) = geometry.endpoints(of: board.move(at: cell), for: player)
        return abs(from.x - to.x) < abs(from.y - to.y)
    }
}

// MARK: - Equipment

/// One contested cell. It never moves: a bridge is claimed, not carried.
@MainActor
struct BridgeSlot: EntityEquipment {
    let id: EquipmentIdentifier
    let entity: Entity
    let initialState: BaseEquipmentState
    /// Index into `GameState.cells`, which is what the engine speaks.
    let cell: Int
}

struct BridgyTabletop: EntityTabletop {
    let id: EquipmentIdentifier
    let entity: Entity
    let side: Double
    let thickness: Double

    /// Stated rather than measured off the entity. The overlay's
    /// `TabletopShape.rectangular(entity:)` is main-actor isolated, and
    /// `Tabletop.shape` is a nonisolated requirement, so the convenient one
    /// cannot satisfy it. We know the dimensions anyway.
    nonisolated var shape: TabletopShape {
        .rectangular(width: Float(side), height: Float(side), thickness: Float(thickness))
    }
}

@MainActor
struct BridgySeat: EntityTableSeat {
    let id: TableSeatIdentifier
    let entity: Entity
    let initialState: TableSeatState
    let player: BoardSide
}

// MARK: - Building the table

/// Builds the RealityKit scene and the matching TabletopKit setup.
///
/// Equipment in TabletopKit is fixed at `TableSetup` — there is no adding a
/// piece later — so the whole table is built for one board size and a size
/// change means building another one.
@MainActor
struct TabletopBoardBuilder {
    let board: Board
    let theme: BoardTheme
    let style: BoardStyle

    func build() -> TabletopBoard {
        let metrics = BoardMetrics(board: board)
        let root = Entity()

        let surface = surfaceEntity(metrics)
        root.addChild(surface)

        let tabletop = BridgyTabletop(
            id: EquipmentIdentifier(0),
            entity: surface,
            side: metrics.side,
            thickness: Self.surfaceThickness
        )
        var setup = TableSetup(tabletop: tabletop)

        let seats = seats(metrics)
        for seat in seats {
            root.addChild(seat.entity)
            setup.add(seat: seat)
        }

        for bank in bankEntities(metrics) { root.addChild(bank) }
        for post in postEntities(metrics) { surface.addChild(post) }
        root.addChild(lightEntity())

        var slots: [BridgeSlot] = []
        slots.reserveCapacity(board.cellCount)
        for cell in 0..<board.cellCount {
            let entity = Entity()
            entity.position = metrics.cellCentre(cell)
            surface.addChild(entity)
            let slot = BridgeSlot(
                // 0 is the tabletop, so equipment starts at 1.
                id: EquipmentIdentifier(cell + 1),
                entity: entity,
                initialState: BaseEquipmentState(
                    parentID: tabletop.id,
                    seatControl: .any,
                    pose: .identity,
                    entity: entity
                ),
                cell: cell
            )
            slots.append(slot)
            setup.add(equipment: slot)
        }

        return TabletopBoard(
            root: root,
            game: TabletopGame(tableSetup: setup),
            metrics: metrics,
            slots: slots,
            seats: seats,
            theme: theme,
            style: style
        )
    }

    /// The water is this deep; the tabletop shape has to agree.
    static let surfaceThickness = 0.05

    /// The stretch of water the bridges cross.
    ///
    /// Physically based rather than unlit, because water is entirely about how
    /// it catches the light — which means the scene has to carry its own
    /// lighting (see `lightEntity`), since a mixed immersive space gives it
    /// almost nothing to reflect.
    private func surfaceEntity(_ metrics: BoardMetrics) -> Entity {
        let mesh = MeshResource.generateBox(
            width: Float(metrics.side),
            height: Float(Self.surfaceThickness),
            depth: Float(metrics.side),
            cornerRadius: Float(metrics.unit * 0.12)
        )
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.05, green: 0.20, blue: 0.35, alpha: 1))
        material.roughness = 0.08
        material.metallic = 0.15
        material.clearcoat = .init(floatLiteral: 0.9)
        material.clearcoatRoughness = .init(floatLiteral: 0.06)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "water"
        entity.addChild(shimmerEntity(metrics))
        return entity
    }

    /// Two broad, near-transparent sheets drifting across each other just above
    /// the surface. Cheaper than displacing a mesh every frame, and at a glance
    /// it reads as moving water rather than a blue slab.
    private func shimmerEntity(_ metrics: BoardMetrics) -> Entity {
        let holder = Entity()
        for (index, tint) in [
            UIColor(red: 0.45, green: 0.75, blue: 0.95, alpha: 0.10),
            UIColor(red: 0.30, green: 0.90, blue: 0.95, alpha: 0.07)
        ].enumerated() {
            let mesh = MeshResource.generateBox(
                width: Float(metrics.side * 0.8),
                height: 0.001,
                depth: Float(metrics.side * 0.8),
                cornerRadius: Float(metrics.side * 0.4)
            )
            var material = UnlitMaterial(color: tint)
            material.blending = .transparent(opacity: .init(floatLiteral: 1))
            let sheet = ModelEntity(mesh: mesh, materials: [material])
            sheet.position = SIMD3(0, Float(Self.surfaceThickness / 2 + 0.002 + Double(index) * 0.002), 0)

            let drift = Float(metrics.unit * 1.4)
            let direction: Float = index == 0 ? 1 : -1
            sheet.position.x -= drift * direction
            var away = sheet.transform
            away.translation.x += drift * 2 * direction
            sheet.move(
                to: away,
                relativeTo: holder,
                duration: 9 + Double(index) * 4,
                timingFunction: .easeInOut
            )
            holder.addChild(sheet)
        }
        return holder
    }

    /// The four banks: the shores each player is trying to join.
    ///
    /// The 2D board never showed this. Here it is the whole point — Down can see
    /// its own two shores ahead and behind, Across sees its own left and right.
    private func bankEntities(_ metrics: BoardMetrics) -> [Entity] {
        let depth = Float(metrics.unit * 1.15)
        let height = Float(Self.surfaceThickness * 0.55)
        let reach = Float(metrics.side) / 2 + depth / 2

        var banks: [Entity] = []
        for side in BoardSide.allCases {
            let alongZ = side == .blue
            // Only one pair runs the full width. If both did they would overlap
            // at all four corners and z-fight, which is exactly what it looked
            // like — the corners of the near bank fizzing red and blue.
            let length = alongZ
                ? Float(metrics.side) + depth * 2
                : Float(metrics.side)
            let mesh = MeshResource.generateBox(
                width: alongZ ? length : depth,
                height: height,
                depth: alongZ ? depth : length,
                cornerRadius: depth * 0.16
            )
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: theme.materialColor(for: side).withAlphaComponent(0.85))
            material.roughness = 0.75
            for sign in [Float(-1), Float(1)] {
                let bank = ModelEntity(mesh: mesh, materials: [material])
                bank.position = alongZ
                    ? SIMD3(0, height * 0.1, sign * reach)
                    : SIMD3(sign * reach, height * 0.1, 0)
                banks.append(bank)
            }
        }
        return banks
    }

    /// The lattice, as posts standing in the water rather than dots on a board.
    private func postEntities(_ metrics: BoardMetrics) -> [Entity] {
        var entities: [Entity] = []
        let radius = Float(metrics.dotRadius * 0.85)
        let height = Float(metrics.unit * 0.9)
        let mesh = MeshResource.generateCylinder(height: height, radius: radius)

        for player in BoardSide.allCases {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: theme.materialColor(for: player))
            material.roughness = 0.55
            for dot in metrics.dots(for: player) {
                let post = ModelEntity(mesh: mesh, materials: [material])
                var position = metrics.postCentre(dot)
                position.y = Float(Self.surfaceThickness / 2) + height / 2 - Float(metrics.unit * 0.12)
                post.position = position
                entities.append(post)
            }
        }
        return entities
    }

    /// One key light plus a soft fill, so the water has something to catch.
    private func lightEntity() -> Entity {
        let holder = Entity()

        let key = DirectionalLight()
        key.light.intensity = 2600
        key.light.color = .white
        key.look(at: .zero, from: SIMD3(0.6, 1.4, 0.5), relativeTo: nil)
        holder.addChild(key)

        let fill = DirectionalLight()
        fill.light.intensity = 900
        fill.light.color = UIColor(red: 0.75, green: 0.88, blue: 1, alpha: 1)
        fill.look(at: .zero, from: SIMD3(-0.8, 0.7, -0.6), relativeTo: nil)
        holder.addChild(fill)

        return holder
    }

    /// Down sits at the near edge, Across to its left — matching the directions
    /// the two players are actually trying to travel.
    private func seats(_ metrics: BoardMetrics) -> [BridgySeat] {
        let reach = Float(metrics.side * 0.85)
        return [
            BridgySeat(
                id: TableSeatIdentifier(0),
                entity: seatEntity(at: SIMD3(0, 0, reach)),
                initialState: TableSeatState(pose: .init(position: .init(x: 0, z: Double(reach)), rotation: .zero)),
                player: .blue
            ),
            BridgySeat(
                id: TableSeatIdentifier(1),
                entity: seatEntity(at: SIMD3(-reach, 0, 0)),
                initialState: TableSeatState(pose: .init(position: .init(x: Double(-reach), z: 0), rotation: .degrees(90))),
                player: .red
            )
        ]
    }

    private func seatEntity(at position: SIMD3<Float>) -> Entity {
        let entity = Entity()
        entity.position = position
        return entity
    }
}

/// Everything the immersive scene needs to show and drive one board.
@MainActor
final class TabletopBoard {
    let root: Entity
    let game: TabletopGame
    let metrics: BoardMetrics
    let slots: [BridgeSlot]
    let seats: [BridgySeat]
    let theme: BoardTheme
    let style: BoardStyle

    /// The bridge model currently standing in each slot, so a redraw only
    /// touches cells that changed.
    private var bridges: [Int: Entity] = [:]

    init(
        root: Entity,
        game: TabletopGame,
        metrics: BoardMetrics,
        slots: [BridgeSlot],
        seats: [BridgySeat],
        theme: BoardTheme,
        style: BoardStyle
    ) {
        self.root = root
        self.game = game
        self.metrics = metrics
        self.slots = slots
        self.seats = seats
        self.theme = theme
        self.style = style
    }

    /// Adds, removes and recolours bridges so the table matches `state`.
    func show(_ state: GameState) {
        for slot in slots {
            let owner = state.cells[slot.cell]
            let existing = bridges[slot.cell]

            switch (owner, existing) {
            case (nil, let entity?):
                entity.removeFromParent()
                bridges[slot.cell] = nil
            case (let owner?, nil):
                let bridge = bridgeEntity(cell: slot.cell, player: owner)
                slot.entity.addChild(bridge)
                bridges[slot.cell] = bridge
            case (let owner?, let entity?):
                // An undo can hand the same cell to the other player.
                entity.removeFromParent()
                let bridge = bridgeEntity(cell: slot.cell, player: owner)
                slot.entity.addChild(bridge)
                bridges[slot.cell] = bridge
            case (nil, nil):
                break
            }
        }
    }

    func clear() {
        for (_, entity) in bridges { entity.removeFromParent() }
        bridges.removeAll()
    }

    /// A bridge rather than a bar: a deck with a rail down each side, lifted
    /// clear of the water and spanning between two of that player's posts.
    private func bridgeEntity(cell: Int, player: BoardSide) -> Entity {
        let deckWidth = Float(metrics.bridgeThickness(style))
        let length = Float(metrics.bridgeLength)
        let deckHeight = deckWidth * 0.34
        let alongZ = metrics.runsAlongZ(cell: cell, player: player)

        let colour = theme.materialColor(for: player)
        var deckMaterial = PhysicallyBasedMaterial()
        deckMaterial.baseColor = .init(tint: colour)
        deckMaterial.roughness = 0.45

        var railMaterial = PhysicallyBasedMaterial()
        railMaterial.baseColor = .init(tint: colour.lighter(by: 0.22))
        railMaterial.roughness = 0.3

        let bridge = Entity()

        let deck = ModelEntity(
            mesh: .generateBox(
                width: alongZ ? deckWidth : length,
                height: deckHeight,
                depth: alongZ ? length : deckWidth,
                cornerRadius: deckHeight * 0.4
            ),
            materials: [deckMaterial]
        )
        bridge.addChild(deck)

        let railThickness = deckWidth * 0.16
        let railHeight = deckWidth * 0.42
        for sign in [Float(-1), Float(1)] {
            let rail = ModelEntity(
                mesh: .generateBox(
                    width: alongZ ? railThickness : length * 0.94,
                    height: railHeight,
                    depth: alongZ ? length * 0.94 : railThickness,
                    cornerRadius: railThickness * 0.5
                ),
                materials: [railMaterial]
            )
            let offset = (deckWidth - railThickness) / 2 * sign
            rail.position = alongZ
                ? SIMD3(offset, deckHeight / 2 + railHeight / 2, 0)
                : SIMD3(0, deckHeight / 2 + railHeight / 2, offset)
            bridge.addChild(rail)
        }

        // Clear of the water, level with the tops of the posts it joins.
        bridge.position = SIMD3(0, Float(metrics.unit * 0.62), 0)
        return bridge
    }
}

private extension BoardTheme {
    /// RealityKit materials want a platform colour, not a SwiftUI one.
    func materialColor(for player: BoardSide) -> UIColor {
        UIColor(color(for: player))
    }
}

private extension UIColor {
    /// A lighter version of the player's colour, for the rails.
    func lighter(by amount: CGFloat) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        return UIColor(
            hue: hue,
            saturation: max(0, saturation - amount * 0.5),
            brightness: min(1, brightness + amount),
            alpha: alpha
        )
    }
}
#endif
