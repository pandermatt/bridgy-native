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

    /// A bridge's deck width, fixed rather than taken from the 2D style.
    ///
    /// The 2D styles are about how lines read on a flat screen — Bolder fills
    /// the whole cell on purpose. In three dimensions that made every bridge a
    /// slab, and thirty of them in a pile a tower taller than the table was wide.
    var deckWidth: Double { unit * 0.42 }

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

    /// The same place, as TabletopKit understands position.
    ///
    /// Equipment is placed from its state's pose, not from the entity's
    /// transform — set the transform and TabletopKit overrides it, which is how
    /// every bridge ended up stacked at the middle of the table.
    func cellPose(_ cell: Int) -> TableVisualState.Pose2D {
        let point = geometry.center(of: board.move(at: cell))
        return .init(
            position: .init(x: Double(point.x) - side / 2, z: Double(point.y) - side / 2),
            rotation: .zero
        )
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

/// Marks the parts of the board you can pick the whole thing up by.
///
/// The banks, and only the banks: a bridge is TabletopKit's to move, so the
/// move-the-board gesture must never claim one.
struct BoardHandleComponent: Component {}

// MARK: - Equipment

/// One contested cell. It never moves: a bridge is claimed, not carried.
struct BridgeSlot: EntityEquipment {
    let id: EquipmentIdentifier
    let entity: Entity
    let initialState: BaseEquipmentState
    /// Index into `GameState.cells`, which is what the engine speaks.
    let cell: Int
    /// Whether Down's bridge across this gap runs away from the player. Across's
    /// is always the perpendicular one, so a single flag covers both.
    let blueRunsAlongZ: Bool

    /// A bridge dropped here settles centred on the gap and square to it.
    ///
    /// Every bridge is modelled pointing the same way, so the turn happens here:
    /// a piece belonging to the side that crosses this gap the other way is
    /// rotated a quarter turn as it lands.
    func layoutChildren(
        for snapshot: TableSnapshot,
        visualState: TableVisualState
    ) -> any EquipmentLayout {
        let children = snapshot.equipment(of: BridgePiece.self, childrenOf: id)
        return .planarStacked(
            layout: children.map { piece, _ in
                let alongZ = piece.owner == .blue ? blueRunsAlongZ : !blueRunsAlongZ
                return EquipmentPose2D(
                    id: piece.id,
                    pose: .init(position: .zero, rotation: alongZ ? .zero : .degrees(90))
                )
            },
            animationDuration: 0.25
        )
    }
}

/// A bridge waiting in a player's tray, to be carried out onto the water.
struct BridgePiece: EntityEquipment {
    let id: EquipmentIdentifier
    let entity: Entity
    let initialState: BaseEquipmentState
    let owner: BoardSide
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

    /// The position to set up. Bridges already played start on their gaps,
    /// so a game carried over from the window carries on where it was.
    var initial: GameState? = nil

    func build() -> TabletopBoard {
        BoardHandleComponent.registerComponent()
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
                    pose: metrics.cellPose(cell),
                    entity: entity
                ),
                cell: cell,
                blueRunsAlongZ: metrics.runsAlongZ(cell: cell, player: .blue)
            )
            slots.append(slot)
            setup.add(equipment: slot)
        }

        // Every piece has to exist now: TabletopKit fixes equipment at
        // TableSetup, so there is no dealing another bridge later. Each side
        // gets exactly as many as it could ever play.
        var pieces: [BridgePiece] = []
        var homes: [EquipmentIdentifier: TableVisualState.Pose2D] = [:]
        var nextID = board.cellCount + 1
        // The cells each side has already bridged, in the order played. A
        // side's first pieces go there; the rest wait in its tray.
        let played = Self.playedCells(in: initial)
        for side in BoardSide.allCases {
            let total = side == .blue
                ? (board.cellCount + 1) / 2
                : board.cellCount / 2
            for index in 0..<total {
                let entity = bridgeModel(metrics: metrics, player: side)
                surface.addChild(entity)
                let home = trayPose(metrics: metrics, side: side, index: index)
                let onCell = played[side].flatMap { index < $0.count ? $0[index] : nil }
                let piece = BridgePiece(
                    id: EquipmentIdentifier(nextID),
                    entity: entity,
                    initialState: BaseEquipmentState(
                        parentID: onCell.map { slots[$0].id } ?? tabletop.id,
                        seatControl: .any,
                        pose: onCell == nil ? home : .identity,
                        entity: entity
                    ),
                    owner: side
                )
                homes[piece.id] = home
                pieces.append(piece)
                setup.add(equipment: piece)
                nextID += 1
            }
        }

        return TabletopBoard(
            root: root,
            game: TabletopGame(tableSetup: setup),
            metrics: metrics,
            slots: slots,
            pieces: pieces,
            seats: seats,
            theme: theme,
            style: style,
            tabletopID: tabletop.id,
            homes: homes
        )
    }

    /// Each side's bridged cells, in the order they were played.
    static func playedCells(in state: GameState?) -> [BoardSide: [Int]] {
        guard let state else { return [:] }
        var result: [BoardSide: [Int]] = [:]
        for move in state.moves {
            let cell = state.board.index(of: move)
            guard let owner = state.cells[cell] else { continue }
            result[owner, default: []].append(cell)
        }
        return result
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
        material.roughness = 0.22
        material.metallic = 0.05
        material.clearcoat = .init(floatLiteral: 0.55)
        material.clearcoatRoughness = .init(floatLiteral: 0.18)
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
                bank.components.set(BoardHandleComponent())
                bank.components.set(InputTargetComponent())
                bank.components.set(HoverEffectComponent())
                bank.generateCollisionShapes(recursive: false)
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
        key.light.intensity = 1700
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

    /// Where a spare bridge waits: in a row of short piles on its own shore.
    ///
    /// TabletopKit stacks equipment that overlaps, physically. Put thirty
    /// bridges in one spot and you get a column climbing off the table; nudge
    /// each one sideways and you get a staircase. A few short piles side by side
    /// read as a supply and stay low enough to reach over.
    private func trayPose(
        metrics: BoardMetrics,
        side: BoardSide,
        index: Int
    ) -> TableVisualState.Pose2D {
        let perPile = 6
        let piles = 6
        let pile = Double(index / perPile % piles)
        let spacing = metrics.deckWidth * 1.7
        let along = (pile - Double(piles - 1) / 2) * spacing
        let outward = metrics.side / 2 + metrics.unit * 2.4

        let position: TableVisualState.Point2D = side == .blue
            ? .init(x: along, z: outward)
            : .init(x: -outward, z: along)
        return .init(position: position, rotation: side == .blue ? .zero : .degrees(90))
    }

    /// A bridge: a deck with a rail down each side, modelled pointing away from
    /// the player. The gap it lands on turns it if that crossing runs the other
    /// way.
    private func bridgeModel(metrics: BoardMetrics, player: BoardSide) -> Entity {
        let deckWidth = Float(metrics.deckWidth)
        let length = Float(metrics.bridgeLength)
        let deckHeight = deckWidth * 0.34

        let colour = theme.materialColor(for: player)
        var deckMaterial = PhysicallyBasedMaterial()
        deckMaterial.baseColor = .init(tint: colour)
        deckMaterial.roughness = 0.45

        var railMaterial = PhysicallyBasedMaterial()
        railMaterial.baseColor = .init(tint: colour.lighter(by: 0.22))
        railMaterial.roughness = 0.3

        let bridge = Entity()
        bridge.addChild(
            ModelEntity(
                mesh: .generateBox(
                    width: deckWidth,
                    height: deckHeight,
                    depth: length,
                    cornerRadius: deckHeight * 0.4
                ),
                materials: [deckMaterial]
            )
        )

        let railThickness = deckWidth * 0.16
        let railHeight = deckWidth * 0.28
        for sign in [Float(-1), Float(1)] {
            let rail = ModelEntity(
                mesh: .generateBox(
                    width: railThickness,
                    height: railHeight,
                    depth: length * 0.94,
                    cornerRadius: railThickness * 0.5
                ),
                materials: [railMaterial]
            )
            rail.position = SIMD3(
                (deckWidth - railThickness) / 2 * sign,
                deckHeight / 2 + railHeight / 2,
                0
            )
            bridge.addChild(rail)
        }

        // Clear of the water, level with the post tops it will join.
        bridge.position = SIMD3(0, Float(metrics.unit * 0.62), 0)
        return bridge
    }

    private func seatEntity(at position: SIMD3<Float>) -> Entity {
        let entity = Entity()
        entity.position = position
        return entity
    }
}

/// Everything the immersive scene needs to run one table.
///
/// It no longer draws bridges. The pieces *are* the bridges: TabletopKit moves
/// a piece entity from the tray onto a slot, so the board's job is just to hold
/// the parts together.
@MainActor
final class TabletopBoard {
    let root: Entity
    let game: TabletopGame
    let metrics: BoardMetrics
    let slots: [BridgeSlot]
    let pieces: [BridgePiece]
    let seats: [BridgySeat]
    let theme: BoardTheme
    let style: BoardStyle
    let tabletopID: EquipmentIdentifier
    /// Where each piece waits in its tray, to send it back for a new game.
    let homes: [EquipmentIdentifier: TableVisualState.Pose2D]

    init(
        root: Entity,
        game: TabletopGame,
        metrics: BoardMetrics,
        slots: [BridgeSlot],
        pieces: [BridgePiece],
        seats: [BridgySeat],
        theme: BoardTheme,
        style: BoardStyle,
        tabletopID: EquipmentIdentifier,
        homes: [EquipmentIdentifier: TableVisualState.Pose2D]
    ) {
        self.tabletopID = tabletopID
        self.homes = homes
        self.root = root
        self.game = game
        self.metrics = metrics
        self.slots = slots
        self.pieces = pieces
        self.seats = seats
        self.theme = theme
        self.style = style
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

extension TabletopBoard {
    /// While the person decides where the board goes it is half there — see
    /// through, so it reads as a preview rather than a game already underway.
    @MainActor
    func setPlacing(_ placing: Bool) {
        root.components.set(OpacityComponent(opacity: placing ? 0.6 : 1))
    }
}
#endif
