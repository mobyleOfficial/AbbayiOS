//
//  AudioDataModel+CoreDataProperties.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 03/07/23.
//
//

import CoreData
import Foundation

class AudioDataModel: NSManagedObject {
    /* Empty */
}

// MARK: - CoreDataProperties
extension AudioDataModel {

    @nonobjc class func fetchRequest() -> NSFetchRequest<AudioDataModel> {
        return NSFetchRequest<AudioDataModel>(entityName: "AudioDataModel")
    }

    @NSManaged var albumName: String?
    @NSManaged var artist: String?
    @NSManaged var currentTime: Double
    @NSManaged var duration: Double
    @NSManaged var imageData: Data?
    @NSManaged var title: String?
    @NSManaged var url: URL?
    @NSManaged var chapters: NSOrderedSet?

}

// MARK: - Generated accessors for chapters
extension AudioDataModel {

    @objc(insertObject:inChaptersAtIndex:)
    @NSManaged func insertIntoChapters(_ value: ChapterDataModel, at idx: Int)

    @objc(removeObjectFromChaptersAtIndex:)
    @NSManaged func removeFromChapters(at idx: Int)

    @objc(insertChapters:atIndexes:)
    @NSManaged func insertIntoChapters(_ values: [ChapterDataModel], at indexes: NSIndexSet)

    @objc(removeChaptersAtIndexes:)
    @NSManaged func removeFromChapters(at indexes: NSIndexSet)

    @objc(replaceObjectInChaptersAtIndex:withObject:)
    @NSManaged func replaceChapters(at idx: Int, with value: ChapterDataModel)

    @objc(replaceChaptersAtIndexes:withChapters:)
    @NSManaged func replaceChapters(at indexes: NSIndexSet, with values: [ChapterDataModel])

    @objc(addChaptersObject:)
    @NSManaged func addToChapters(_ value: ChapterDataModel)

    @objc(removeChaptersObject:)
    @NSManaged func removeFromChapters(_ value: ChapterDataModel)

    @objc(addChapters:)
    @NSManaged func addToChapters(_ values: NSOrderedSet)

    @objc(removeChapters:)
    @NSManaged func removeFromChapters(_ values: NSOrderedSet)

}

// MARK: - Identifiable
extension AudioDataModel: Identifiable {
    /* Empty */
}
