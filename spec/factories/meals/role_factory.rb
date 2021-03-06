# frozen_string_literal: true

FactoryBot.define do
  factory :meal_role, class: "Meals::Role" do
    sequence(:title) { |n| "#{Faker::Job.title} #{n}" }
    community { Defaults.community }
    time_type { "date_only" }
    description { Faker::Lorem.paragraph }

    trait :head_cook do
      special { "head_cook" }
      title { "Head Cook" }
    end

    trait :with_reminder do
      after(:build) do |role|
        role.reminders.build(build(:meal_role_reminder, role: role).attributes)
      end
    end

    trait :inactive do
      deactivated_at { Time.current - 1 }
    end
  end
end
