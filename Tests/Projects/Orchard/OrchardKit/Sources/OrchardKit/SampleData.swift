import Foundation

/// The orchard every preview shows: built by replaying a log through the reducer.
public enum SampleOrchard {
    public static let empty = OrchardState(name: "Hillside", trees: [])

    public static let log: [OrchardAction] = [
        .plant(Tree(id: "t1", name: "Old Bramley", fruit: .apple, plantedYear: 1987)),
        .plant(Tree(id: "t2", name: "Conference", fruit: .pear, plantedYear: 2004)),
        .plant(Tree(id: "t3", name: "Victoria", fruit: .plum, plantedYear: 2012)),
        .plant(Tree(id: "t4", name: "Morello", fruit: .cherry, plantedYear: 2019)),
        .record(treeID: "t4", Harvest(id: "h1", day: 118, kilograms: 6.5, note: "Netted in time")),
        .record(treeID: "t3", Harvest(id: "h2", day: 171, kilograms: 14, note: "Wasps at the top")),
        .record(treeID: "t1", Harvest(id: "h3", day: 196, kilograms: 31.5)),
        .record(treeID: "t2", Harvest(id: "h4", day: 189, kilograms: 22, note: "Picked firm")),
        .record(treeID: "t1", Harvest(id: "h5", day: 210, kilograms: 27, note: "Windfalls for cider")),
        .rename(treeID: "t4", to: "Morello by the gate"),
    ]

    public static let state = empty.applying(log)
}
