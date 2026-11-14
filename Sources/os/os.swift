// `import os` (and `import os.log`, `os.signpost`): unified logging, signposts and unfair locks.
// Messages are formatted lazily and dropped: a screenshot has no log to write them to. Locks are real.
@_exported import Foundation
