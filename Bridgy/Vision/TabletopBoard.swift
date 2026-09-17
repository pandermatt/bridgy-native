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

        for dot in dotEntities(metrics) { surface.addChild(dot) }

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

    /// The playing surface is this thick; the tabletop shape has to agree.
    static let surfaceThickness = 0.012

    private func surfaceEntity(_ metrics: BoardMetrics) -> Entity {
        let thickness = Self.surfaceThickness
        let mesh = MeshResource.generateBox(
            width: Float(metrics.side),
            height: Float(thickness),
            depth: Float(metrics.side),
            cornerRadius: Float(metrics.unit * 0.2)
        )
        // Unlit throughout. A mixed immersive space lights physically-based
        // materials from the surroundings, and in the simulator there is
        // essentially nothing to reflect, so a PBR board renders invisible.
        // Flat colour is also simply what this game looks like.
        let material = UnlitMaterial(color: UIColor(white: 0.10, alpha: 1))
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "tabletop"
        return entity
    }

    /// The lattice itself. Always drawn here, whatever the 2D style says:
    /// without dots a bare table gives you nothing to aim a bridge at.
    private func dotEntities(_ metrics: BoardMetrics) -> [Entity] {
        var entities: [Entity] = []
        let radius = Float(metrics.dotRadius)
        let mesh = MeshResource.generateSphere(radius: radius)
        for player in BoardSide.allCases {
            let material = UnlitMaterial(
                color: theme.materialColor(for: player).withAlphaComponent(0.55)
            )
            for dot in metrics.dots(for: player) {
                let entity = ModelEntity(mesh: mesh, materials: [material])
                var position = metrics.dotCentre(dot)
                position.y = Float(metrics.unit * 0.10)
                entity.position = position
                entities.append(entity)
            }
        }
        return entities
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

    private func bridgeEntity(cell: Int, player: BoardSide) -> Entity {
        let thickness = Float(metrics.bridgeThickness(style))
        let length = Float(metrics.bridgeLength)
        let alongZ = metrics.runsAlongZ(cell: cell, player: player)
        let mesh = MeshResource.generateBox(
            width: alongZ ? thickness : length,
            height: thickness,
            depth: alongZ ? length : thickness,
            cornerRadius: thickness * 0.45
        )
        let material = UnlitMaterial(color: theme.materialColor(for: player))
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = SIMD3(0, thickness * 0.5 + 0.006, 0)
        return entity
    }
}

private extension BoardTheme {
    /// RealityKit materials want a platform colour, not a SwiftUI one.
    func materialColor(for player: BoardSide) -> UIColor {
        UIColor(color(for: player))
    }
}
#endif
