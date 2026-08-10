import Foundation
import TaggingCore

enum StoreError: Error {
    case duplicateTag(existing: Tag)
    case categoryNotFound(id: UUID)
    case tagNotFound(id: UUID)
    case cannotDeleteBuiltInCategory
}
