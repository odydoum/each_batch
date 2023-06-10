# frozen_string_literal: true
require "where_row"
require "each_batch/plucked_batch_enumerator"

module EachBatch
  class BatchEnumerator
    include Enumerable

    DEFAULT_BATCH_SIZE = 1000

    attr_reader :relation, :order, :keys

    def initialize(relation, of: DEFAULT_BATCH_SIZE, load: false, order: :asc, keys: nil)
      raise ArgumentError, 'Batch size must be a positive integer' if of != of.to_i || of <= 0 
      
      order = order.to_s
      raise ArgumentError, 'Invalid order' if !order.casecmp('desc').zero? && !order.casecmp('asc').zero?
      
      pk_name = relation.primary_key.to_s
      keys = keys&.map(&:to_s) || [pk_name.to_s]

      # TODO: This is for safety, since there is no easy way to determine whether the order
      # is deterministic or not. PK guarantees that.
      raise ArgumentError, 'Primary key must be that last key' if keys.last != pk_name

      if relation.select_values.present? && (relation.select_values.map(&:to_s) & keys).to_set != keys.to_set
        raise ArgumentError, 'Not all keys are included in the custom select clause'
      end

      @relation = relation
      @of = of
      @load = load
      @order = order
      @keys = keys
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
      pk = relation.primary_key.to_sym

      loop do
        # consistent with rails load behavior.
        if @load
          records = yielded_relation.records
          yielded_relation = relation.where(pk => records.map(&pk))
          yielded_relation.send(:load_records, records)
        end

        yield yielded_relation

        offsets =
          if @load || yielded_relation.loaded?
            break if yielded_relation.length < batch_size

            yielded_relation.last.attributes_before_type_cast&.values_at(*keys)
          else
            # we need an additional query to fetch the last key set
            offsets = yielded_relation.offset(batch_size - 1).limit(1).pluck(*keys).first

            break if offsets.nil?

            Array.wrap(offsets)
          end

        yielded_relation = batch_relation.where_row(*keys).public_send(op, *offsets)
      end
    end

    def each_record(&block)
      return to_enum(:each_record) unless block_given?

      each { |yielded_relation| yielded_relation.to_a.each(&block) }
    end

    #
    # Pluck selected columns in batches. The batching is the one specified
    # on the { BatchEnumerator } instance.
    #
    # @param [Array<Symbol, String>] pluck_keys The keys of the columns to pluck.
    #
    # @return [EachBatch::PluckedBatchEnumerator] The batch enumerator
    #
    # @yieldparam [Array<Object>] x The array of the plucked values
    def pluck(*pluck_keys, &block)
      plucked_batch_enumerator = ::EachBatch::PluckedBatchEnumerator.new(
        relation,
        of: batch_size,
        order: order,
        keys: keys,
        pluck_keys: pluck_keys.map(&:to_s)
      )

      return plucked_batch_enumerator unless block_given?

      plucked_batch_enumerator.each(&block)
    end
  end
end
