# frozen_string_literal: true
require "each_batch/version"
require "each_batch/active_record/relation"
require "each_batch/active_record/base"

require "active_record"

module EachBatch; end

ActiveRecord::Relation.prepend ::EachBatch::ActiveRecord::Relation
ActiveRecord::Base.extend ::EachBatch::ActiveRecord::Base
