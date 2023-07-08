//
//  ChapterDataModel+CoreDataProperties.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 03/07/23.
//
//

import Foundation
import CoreData

public class ChapterDataModel: NSManagedObject {
    /* Empty */
}

// MARK: - CoreDataProperties
extension ChapterDataModel {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChapterDataModel> {
        return NSFetchRequest<ChapterDataModel>(entityName: "ChapterDataModel")
    }

    @NSManaged public var title: String?
    @NSManaged public var startTime: Double
    @NSManaged public var duration: Double
    @NSManaged public var audio: AudioDataModel?

}

// MARK: - Identifiable
extension ChapterDataModel: Identifiable {
    /* Empty */
}
