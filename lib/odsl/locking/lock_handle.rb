module Odsl
  module Locking
    LockHandle = Struct.new(:client, :lock_info) do
      def unlock
        client.unlock(lock_info)
      end
    end
  end
end
