# frozen_string_literal: true

module Work
  # Models a single signup for a single shift.
  class Assignment < ApplicationRecord
    acts_as_tenant :cluster

    belongs_to :shift, inverse_of: :assignments, counter_cache: true, touch: true
    belongs_to :user

    scope :in_community, ->(c) { joins(shift: {job: :period}).where("work_periods.community_id": c.id) }

    # Can't merge the order by name scope due to an error/bug with ActsAsTenant
    scope :by_user_name, -> { joins(:user).order(User::NAME_ORDER) }

    delegate :job, :community, :period_draft?, :fixed_slot?, :full_community?, to: :shift
    delegate :hours, to: :shift, prefix: true

    before_save do
      self.preassigned = period_draft?
    end
  end
end
