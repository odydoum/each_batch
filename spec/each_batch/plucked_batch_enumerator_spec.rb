RSpec.describe EachBatch::PluckedBatchEnumerator do 
  subject(:enumerator) { described_class.new(relation, opts) }

  before do
    class TestRecord < ActiveRecord::Base
    end

    ActiveRecord::Schema.verbose = false
    ActiveRecord::Schema.define(version: 1) do
      create_table :test_records do |t|
        t.integer :col
        t.timestamps
      end
    end
  end

  let(:relation) { TestRecord.all }
  let(:opts) do
    {
      of: batch_size,
      order: :asc,
      keys: keys,
      pluck_keys: pluck_keys
    }
  end

  let(:batch_size) { 2 }
  let(:keys) { [:id] }
  let(:pluck_keys) { [:id, :created_at] }

  describe 'argument validation' do
    context 'when all keys are included in the requested pluck keys' do
      it { expect{ subject }.not_to raise_error }
    end

    context 'when not all keys are included in the requested pluck keys' do
      let(:keys) { [:created_at, :id] }
      let(:pluck_keys) { [:id] }

      it { expect{ subject }.to raise_error(ArgumentError) }
    end
  end

  describe '#batch_size' do
    subject { enumerator.batch_size }

    it 'returns the value of :of' do
      is_expected.to eq(opts[:of])
    end
  end

  describe '#each' do
    let(:expected_first_batch) do
      relation.limit(batch_size).order(id: :asc)
    end

    context 'when called with no block' do
      it 'returns itself' do
        expect(subject.each).to be(enumerator)
      end
    end

    context 'when the table is empty' do
      it 'does not yield' do
        expect { |b| subject.each(&b) }.not_to yield_control
      end
    end

    context 'when the table has more records than the batch size' do
      context 'and it is not a multiple of batch_size' do
        before do
          (2 * batch_size + 1).times { TestRecord.create! }
        end

        let(:ordered_ids) { relation.order(id: :asc).ids }

        it 'yields until no more records can be found, ordered by ids' do
          expect { |b| subject.map { |r| r.to_a }.each(&b) }.
            to yield_successive_args(
              relation.where(id: ordered_ids[0..1]).order(id: :asc).pluck(*pluck_keys),
              relation.where(id: ordered_ids[2..3]).order(id: :asc).pluck(*pluck_keys),
              relation.where(id: ordered_ids[4]).order(id: :asc).pluck(*pluck_keys)
            )
        end
      end

      context 'and it is a multiple of batch_size' do
        before do
          (2 * batch_size).times { TestRecord.create! }
        end

        let(:ordered_ids) { relation.order(id: :asc).ids }

        it 'yields until no more records can be found, ordered by ids' do
          expect { |b| subject.map { |r| r.to_a }.each(&b) }.
            to yield_successive_args(
              relation.where(id: ordered_ids[0..1]).order(id: :asc).pluck(*pluck_keys),
              relation.where(id: ordered_ids[2..3]).order(id: :asc).pluck(*pluck_keys),
            )
        end
      end
    end
  end

  describe '#each_row' do
    context 'when the table is empty' do
      it 'does not yield anything' do
        expect { |b| subject.each_row(&b) }.not_to yield_control
      end
    end

    context 'when the table is not empty' do
      let!(:records) { 4.times.map { TestRecord.create! } }

      let(:rows) { TestRecord.all.order(id: :asc).pluck(*pluck_keys) }

      it 'yields for each row found, ordered' do
        expect { |b| subject.each_row(&b) }.
          to yield_successive_args(*rows)
      end
    end
  end
end
