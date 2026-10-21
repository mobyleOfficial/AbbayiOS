//
//  ChapterDataModel+CoreDataProperties.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 03/07/23.
//
//

import CoreData
import Foundation

class ChapterDataModel: NSManagedObject {
    /* Empty */
}

// MARK: - CoreDataProperties
extension ChapterDataModel {

    @nonobjc class func fetchRequest() -> NSFetchRequest<ChapterDataModel> {
        return NSFetchRequest<ChapterDataModel>(entityName: "ChapterDataModel")
    }

    @NSManaged var title: String?
    @NSManaged var startTime: Double
    @NSManaged var duration: Double
    @NSManaged var remoteURL: URL?
    @NSManaged var expectedBytes: Int64
    @NSManaged var audio: AudioDataModel?

}

// MARK: - Identifiable
extension ChapterDataModel: Identifiable {
    /* Empty */
}
