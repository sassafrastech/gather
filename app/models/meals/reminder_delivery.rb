# frozen_string_literal: true

module Meals
  # Tracks the delivery of a given reminder for a given assignment, in order to prevent duplicate deliveries.
  class ReminderDelivery < ApplicationRecord
    acts_as_tenant :cluster

    belongs_to :reminder, class_name: "Meals::RoleReminder", inverse_of: :deliveries
    belongs_to :assignment, class_name: "Meals::Assignment", inverse_of: :reminder_deliveries

    delegate :job, :abs_time, :rel_magnitude, :rel_sign, :abs_time?, :rel_days?, to: :reminder
    delegate :community, to: :assignment

    before_save :compute_deliver_at

    # shift has multiple assignments, send to all
    # assignment has single user, send to one only
    # role may have other assignments for that particular meal; this is where the names kind of change meaning, confusing
    # duck type for now
    def assignments
      [assignment]
    end

    private

    def compute_deliver_at
      self.deliver_at =
        if abs_time?
          abs_time
        elsif rel_days?
          assignment.starts_at.midnight + rel_sign * rel_magnitude.days + 9.hours
        else
          assignment.starts_at + rel_sign * rel_magnitude.hours
        end
    end
  end
end