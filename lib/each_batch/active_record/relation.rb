# frozen_string_literal: true
require "each_batch/batch_enumerator"

module EachBatch
  module ActiveRecord
    module Relation
      #
      # Process records in batches. Optionally specify the keys by which to
      # calculate the batch offsets.
      #
      # @param [Integer] of 1000 The batch size
      # @param [Boolean] load false Whether the batch records should be loaded
      # @param [Symbol, String] order :asc The order of processing
      # @param [Array<String, Symbol>] keys The keys used for the ordering
      #
      # @return [EachBatch::BatchEnumerator] The batch enumerator
      #
      # @yieldparam [ActiveRecord::Relation] x The relation that corresponds to the batch
      def each_batch(of: 1000, load: false, order: :asc, keys: [primary_key], &block)
        batch_enumerator = ::EachBatch::BatchEnumerator.new(
          self,
          of: of,
          load: load,
          order: order,
          keys: keys
        )

        return batch_enumerator unless block_given?

        batch_enumerator.each(&block)
      end
    end
  end
end
