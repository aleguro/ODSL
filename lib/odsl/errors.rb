module Odsl
  class Error < StandardError; end

  class LockError                 < Error; end
  class LockingNotConfiguredError < Error; end
  class AlreadyRunningError       < Error; end
  class ContextNotFoundError      < Error; end
end
