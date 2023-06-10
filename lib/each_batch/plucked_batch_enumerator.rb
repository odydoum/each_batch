# frozen_string_literal: true
require "where_row"

module EachBatch
  class PluckedBatchEnumerator
    include Enumerable

    attr_reader :relation, :order, :keys

    def initialize(relation, of:, order:, keys:, pluck_keys:)
      if pluck_keys.present? && (pluck_keys & keys).to_set != keys.to_set
        raise ArgumentError, 'Not all keys are included in the custom select clause for pluck'
      end

      @relation = relation
      @of = of
      @order = order
      @keys = keys
      @pluck_keys = pluck_keys
      @key_indices = keys.map { |key| pluck_keys.index(key) }
    end

    def batch_size
      @of
    end

    def each
      return self unless block_given?

      batch_relation = relation.reorder(keys.product([order]).to_h).limit(batch_size)
      batch_relation.skip_query_cache! # Retaining the results in the query cache would undermine the point of batching

      yielded_relation = batch_relation
      op = order.to_s.casecmp('desc').zero? ? :lt : :gt
      last_idx = batch_size - 1

      pk = relation.primary_key.to_sym
      single_pluck_key = @pluck_keys.length == 1


      loop do
        results = yielded_relation.pluck(*@pluck_keys)

        break if results.empty?

        yield results

        # grab the offsets from the plucked results
        offsets =
          if single_pluck_key
            results[last_idx]
          else
            results[last_idx]&.values_at(*@key_indices)
          end

        break if offsets.nil?

        yielded_relation = batch_relation.where_row(*keys).public_send(op, *offsets)
      end
    end

    def each_row(&block)
      return to_enum(:each_row) unless block_given?

      each { |row_batch| row_batch.each(&block) }
    end
  end
end
