//
//  AudioDataModel+CoreDataProperties.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 03/07/23.
//
//

import Foundation
import CoreData

public class AudioDataModel: NSManagedObject {
    /* Empty */
}

// MARK: - CoreDataProperties
extension AudioDataModel {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<AudioDataModel> {
        return NSFetchRequest<AudioDataModel>(entityName: "AudioDataModel")
    }

    @NSManaged public var albumName: String?
    @NSManaged public var artist: String?
    @NSManaged public var currentTime: Double
    @NSManaged public var duration: Double
    @NSManaged public var imageData: Data?
    @NSManaged public var title: String?
    @NSManaged public var url: URL?
    @NSManaged public var chapters: NSOrderedSet?

}

// MARK: - Generated accessors for chapters
extension AudioDataModel {

    @objc(insertObject:inChaptersAtIndex:)
    @NSManaged public func insertIntoChapters(_ value: ChapterDataModel, at idx: Int)

    @objc(removeObjectFromChaptersAtIndex:)
    @NSManaged public func removeFromChapters(at idx: Int)

    @objc(insertChapters:atIndexes:)
    @NSManaged public func insertIntoChapters(_ values: [ChapterDataModel], at indexes: NSIndexSet)

    @objc(removeChaptersAtIndexes:)
    @NSManaged public func removeFromChapters(at indexes: NSIndexSet)

    @objc(replaceObjectInChaptersAtIndex:withObject:)
    @NSManaged public func replaceChapters(at idx: Int, with value: ChapterDataModel)

    @objc(replaceChaptersAtIndexes:withChapters:)
    @NSManaged public func replaceChapters(at indexes: NSIndexSet, with values: [ChapterDataModel])

    @objc(addChaptersObject:)
    @NSManaged public func addToChapters(_ value: ChapterDataModel)

    @objc(removeChaptersObject:)
    @NSManaged public func removeFromChapters(_ value: ChapterDataModel)

    @objc(addChapters:)
    @NSManaged public func addToChapters(_ values: NSOrderedSet)

    @objc(removeChapters:)
    @NSManaged public func removeFromChapters(_ values: NSOrderedSet)

}

// MARK: - Identifiable
extension AudioDataModel: Identifiable {
    /* Empty */
}
