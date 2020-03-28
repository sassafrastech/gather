# frozen_string_literal: true

module Meals
  # Updates RoleReminderDeliverys for various events
  class RoleReminderMaintainer < ReminderMaintainer
    include Singleton

    def formula_saved(meals, roles)
      # We have to iterate over each pair of 1. reminders associated with this formula and
      # 2. meals associated with this formula and ensure that a RoleReminderDelivery exists for each pair.
      # If a role is removed from the formula, the role doesn't get removed from the meal, so we don't
      # need to worry about deleting the deliveries.
      #
      # We only consider recent or future meals because otherwise we'd have to iterate over quite a lot
      # of meals for a mature community, and with little benefit, since reminders only usually relate
      # to events in the future or recent past.
      reminders_for_roles = reminders(roles).includes(:role)
      pairs = meal_reminder_pairs_with_deliveries(reminders_for_roles)
      current_meals(meals).find_each do |meal|
        reminders_for_roles.each do |reminder|
          next if pairs[[meal.id, reminder.id]]
          RoleReminderDelivery.new(meal: meal, reminder: reminder).calculate_and_save
        end
      end
    end

    def meal_saved(meal, roles, deliveries)
      return deliveries.destroy_all if meal.cancelled?

      # Run callbacks on existing deliveries to ensure recomputation.
      deliveries.includes(reminder: :role).find_each(&:calculate_and_save)

      # Create any missing deliveries.
      roles.includes(:reminders).flat_map(&:reminders).each do |reminder|
        deliveries.find_or_initialize_by(reminder: reminder).calculate_and_save
      end
    end

    def role_saved(reminders)
      RoleReminderDelivery.where(reminder_id: reminders.pluck(:id))
        .includes(:meal, :reminder).find_each(&:calculate_and_save)
    end

    private

    def reminders(roles)
      Meals::RoleReminder.where(role_id: roles.pluck(:id))
    end

    def current_meals(meals)
      meals.not_cancelled.future_or_recent(RoleReminder::MAX_FUTURE_DISTANCE)
    end

    def meal_reminder_pairs_with_deliveries(reminders)
      RoleReminderDelivery.where(reminder_id: reminders.pluck(:id))
        .index_by { |d| [d.meal_id, d.reminder_id] }
    end

    def remindable_events(reminder)
      current_meals(Meal.where(formula_id: reminder.role.formula_ids))
    end

    def delivery_type
      "Meals::RoleReminderDelivery"
    end

    def event_key
      :meal
    end

    def eager_loads
      :meal
    end
  end
end
