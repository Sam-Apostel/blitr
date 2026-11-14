import Foundation

/// One picking of a tree.
public struct Harvest: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    /// Day of the season, counted from the first of March.
    public var day: Int
    public var kilograms: Double
    public var note: String

    public init(id: String, day: Int, kilograms: Double, note: String = "") {
        self.id = id
        self.day = day
        self.kilograms = kilograms
        self.note = note
    }
}

public struct Tree: Identifiable, Equatable, Codable, Sendable {
    public enum Fruit: String, Codable, Sendable, CaseIterable { case apple, pear, plum, cherry }

    public var id: String
    public var name: String
    public var fruit: Fruit
    public var plantedYear: Int
    public var harvests: [Harvest]

    public init(id: String, name: String, fruit: Fruit, plantedYear: Int, harvests: [Harvest] = []) {
        self.id = id
        self.name = name
        self.fruit = fruit
        self.plantedYear = plantedYear
        self.harvests = harvests
    }

    public var totalKilograms: Double { harvests.reduce(0) { $0 + $1.kilograms } }
}

public struct OrchardState: Equatable, Codable, Sendable {
    public var name: String
    public var trees: [Tree]

    public init(name: String, trees: [Tree]) {
        self.name = name
        self.trees = trees
    }

    public var totalKilograms: Double { trees.reduce(0) { $0 + $1.totalKilograms } }
    public var bestTree: Tree? { trees.max { $0.totalKilograms < $1.totalKilograms } }
}
