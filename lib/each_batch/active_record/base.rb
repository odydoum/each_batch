module EachBatch
  module ActiveRecord
    module Base
      def each_batch(*args, **kwargs, &block)
        all.each_batch(*args, **kwargs, &block)
      end
    end
  end
end
