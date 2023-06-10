RSpec.describe EachBatch::BatchEnumerator do
  subject(:enumerator) { described_class.new(relation, opts) }

  before do
    class TestRecord < ActiveRecord::Base
    end

    ActiveRecord::Schema.verbose = false
    ActiveRecord::Schema.define(version: 1) do
      create_table :test_records do |t|
        t.timestamps
      end
    end
  end

  let(:relation) { TestRecord.all }
  let(:opts) { {} }

  describe 'argument validation' do
    describe 'of' do
      let(:opts) { { of: batch_size} }

      context 'when batch size is negative' do
        let(:batch_size) { -1 }

        it { expect{ subject }.to raise_error(ArgumentError) }
      end

      context 'when batch size is zero' do
        let(:batch_size) { 0 }

        it { expect{ subject }.to raise_error(ArgumentError) }
      end

      context 'when batch size is a float' do
        let(:batch_size) { 1.1 }

        it { expect{ subject }.to raise_error(ArgumentError) }
      end

      context 'when batch size is nil' do
        let(:batch_size) { nil }

        it { expect{ subject }.to raise_error(ArgumentError) }
      end

      context 'when batch size is not a number' do
        let(:batch_size) { 'asdf' }

        it { expect{ subject }.to raise_error(ArgumentError) }
      end
    end

    describe 'order' do
      let(:opts) { { order: order} }

      context 'when order is "desc"' do
        let(:order) { 'desc' }

        it { expect{ subject }.not_to raise_error }
      end

      context 'when order is "asc"' do
        let(:order) { 'asc' }

        it { expect{ subject }.not_to raise_error }
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it { expect{ subject }.not_to raise_error }
      end

      context 'when order is :asc' do
        let(:order) { :asc }

        it { expect{ subject }.not_to raise_error }
      end

      context 'when the case does not match' do
        let(:order) { :Asc }

        it { expect{ subject }.not_to raise_error }
      end

      context 'when not an order' do
        let(:order) { :something_else }

        it { expect{ subject }.to raise_error(ArgumentError) }
      end
    end
  end

  describe '#batch_size' do
    subject { enumerator.batch_size }
    context 'when no explicit argument is given' do
      it 'sets a default value' do
        is_expected.to eq(1000)
      end
    end

    context 'when explicit argument is given' do
      let(:opts) { { of: 30 } }

      it 'returns that value' do
        is_expected.to eq(opts[:of])
      end
    end
  end

  describe '#each' do
    let(:opts) do
      {
        of: batch_size,
        load: should_load
      }
    end

    let(:batch_size) { 2 }
    let(:should_load) { false }

    let(:expected_first_batch) do
      relation.limit(batch_size).order(id: :asc)
    end

    context 'when called with no block' do
      it 'returns itself' do
        expect(subject.each).to be(enumerator)
      end
    end

    context 'when the table is empty' do
      it 'yields once the relation of the first batch ordered by id' do
        expect { |b| subject.each(&b) }.
          to yield_successive_args(expected_first_batch)
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
              relation.find(ordered_ids[0..1]),
              relation.find(ordered_ids[2..3]),
              [relation.find(ordered_ids[4])]
            )
        end
      end

      context 'and it is a multiple of batch_size' do
        before do
          (2 * batch_size).times { TestRecord.create! }
        end

        let(:ordered_ids) { relation.order(id: :asc).ids }

        it 'yields one additional empty relation' do
          expect { |b| subject.map { |r| r.to_a }.each(&b) }.
            to yield_successive_args(
              relation.find(ordered_ids[0..1]),
              relation.find(ordered_ids[2..3]),
              []
            )
        end
      end
    end

    context 'when keys are specified' do
      let(:opts) do
        {
          of: batch_size,
          load: should_load,
          keys: keys
        }
      end

      let(:keys) { [:created_at, :id] }

      let(:expected_first_batch) do
        relation.limit(batch_size).order(created_at: :asc, id: :asc)
      end

      context 'when the table is empty' do
        it 'yields once the relation of the first batch ordered by id' do
          expect { |b| subject.each(&b) }.
            to yield_successive_args(expected_first_batch)
        end
      end

      context 'when the table has more records than the batch size' do
        context 'and it is not a multiple of batch_size' do
          before do
            TestRecord.create!(created_at: 1.day.ago)
            TestRecord.create!(created_at: 3.day.ago)
            TestRecord.create!(created_at: 2.day.ago)
            TestRecord.create!(created_at: 6.day.ago)
            TestRecord.create!(created_at: 2.day.ago)
          end

          let(:ordered_ids) { relation.order(created_at: :asc, id: :asc).ids }

          it 'yields until no more records can be found, ordered by keys' do
            expect { |b| subject.map { |r| r.to_a }.each(&b) }.
              to yield_successive_args(
                relation.find(ordered_ids[0..1]),
                relation.find(ordered_ids[2..3]),
                [relation.find(ordered_ids[4])]
              )
          end
        end

        context 'and it is a multiple of batch_size' do
          before do
            (2 * batch_size).times { TestRecord.create! }
          end

          let(:ordered_ids) { relation.order(id: :asc).ids }

          it 'yields one additional empty relation' do
            expect { |b| subject.map { |r| r.to_a }.each(&b) }.
              to yield_successive_args(
                relation.find(ordered_ids[0..1]),
                relation.find(ordered_ids[2..3]),
                []
              )
          end
        end
      end
    end

    context 'when the primary key is not named :id' do
      before do
        class PrimaryKeyRecord < ActiveRecord::Base
          self.primary_key = "primary_id"
        end

        ActiveRecord::Schema.verbose = false
        ActiveRecord::Schema.define(version: 1) do
          create_table :primary_key_records, id: false do |t|
            t.primary_key :primary_id
            t.timestamps
          end
        end
      end

      let(:relation) { PrimaryKeyRecord.all }

      context 'when the table has more records than the batch size' do
        context 'and it is not a multiple of batch_size' do
          before do
            (2 * batch_size + 1).times { PrimaryKeyRecord.create! }
          end

          let(:ordered_ids) { relation.order(primary_id: :asc).pluck(:primary_id) }

          it 'yields until no more records can be found, ordered by ids' do
            expect { |b| subject.map { |r| r.to_a }.each(&b) }.
              to yield_successive_args(
                relation.find(ordered_ids[0..1]),
                relation.find(ordered_ids[2..3]),
                [relation.find(ordered_ids[4])]
              )
          end
        end

        context 'and it is a multiple of batch_size' do
          before do
            (2 * batch_size).times { PrimaryKeyRecord.create! }
          end

          let(:ordered_ids) { relation.order(primary_id: :asc).pluck(:primary_id) }

          it 'yields one additional empty relation' do
            expect { |b| subject.map { |r| r.to_a }.each(&b) }.
              to yield_successive_args(
                relation.find(ordered_ids[0..1]),
                relation.find(ordered_ids[2..3]),
                []
              )
          end
        end
      end
    end
  end

  describe '#each_record' do
    let(:opts) { { of: batch_size } }

    let(:batch_size) { 2 }

    context 'when the table is empty' do
      it 'does not yield anything' do
        expect { |b| subject.each_record(&b) }.not_to yield_control
      end
    end

    context 'when the table is not empty' do
      let!(:records) { 4.times.map { TestRecord.create! } }

      it 'yields for each record found, ordered' do
        expect { |b| subject.each_record(&b) }.
          to yield_successive_args(*records)
      end
    end
  end

  describe '#pluck' do
    let(:opts) { { of: 2 } }

    context 'when called without a block' do
      it 'returns a pluck enumerator' do
        expect(subject.pluck(:id)).to be_a(EachBatch::PluckedBatchEnumerator)
      end
    end

    context 'when called with a block' do
      context 'and some records exist' do
        let!(:records) { 4.times.map { TestRecord.create! } }

        it 'yields for each row batch found, ordered' do
          expect { |b| subject.pluck(:id, &b) }.
            to yield_successive_args(records.first(2).map(&:id), records.last(2).map(&:id))
        end
      end

      context 'and no records exist' do
        it 'does not yield' do
          expect { |b| subject.pluck(:id, &b) }.not_to yield_control
        end
      end
    end
  end
end
