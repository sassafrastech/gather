# frozen_string_literal: true

class CreateMealRolesAndLinkToFormulas < ActiveRecord::Migration[5.1]
  def up
    each_community do |community|
      # For each community, create head cook role
      # plus one for each of the roles in settings.meals.extra_roles.
      # Add shift times and reminders according to settings.
      roles = [create_role(community, :head_cook)]
      extra_roles(community).each do |role_key|
        next unless TITLES[role_key] # Skip invalid roles
        roles << create_role(community, role_key)
      end

      # Link roles to existing formulas.
      Meals::Formula.in_community(community).each do |formula|
        formula.update!(role_ids: roles.map(&:id))
      end
    end
  end

  private

  TITLES = {head_cook: "Head Cook", asst_cook: "Assistant Cook",
            cleaner: "Cleaner", table_setter: "Table Setter"}.freeze
  COUNTS = {head_cook: 1, asst_cook: 2, cleaner: 3, table_setter: 1}.freeze

  def create_role(community, key)
    head_cook = key == :head_cook
    attrs = {}
    attrs[:community] = community
    attrs[:count_per_meal] = COUNTS[key]
    attrs[:description] = TITLES[key]
    attrs[:shift_start] = head_cook ? nil : setting(community, %w[default_shift_times start] << key).to_i
    attrs[:shift_end] = head_cook ? nil : setting(community, %w[default_shift_times end] << key).to_i
    attrs[:special] = head_cook ? key.to_s : nil
    attrs[:time_type] = head_cook ? "date_only" : "date_time"
    attrs[:title] = TITLES[key]
    attrs[:reminders_attributes] = [{
      rel_magnitude: setting(community, %w[reminder_lead_times] << (head_cook ? key : :job)).to_i,
      rel_unit_sign: "days_before"
    }]
    Meals::Role.create!(attrs)
  end

  # Need to query b/c the code for getting it nicely will have disappeared by the time this is run.
  def extra_roles(community)
    setting(community, %w[extra_roles]).strip.split(/\s*,\s*/).map(&:to_sym)
  end

  def setting(community, path)
    last = path.pop
    path = path.unshift("meals").map { |p| "'#{p}'" }.unshift("settings").join("->") << "->>'#{last}'"
    execute("SELECT #{path} FROM communities WHERE id = #{community.id}").to_a[0].values[0]
  end

  def each_community
    ActsAsTenant.without_tenant do
      Cluster.all.each do |cluster|
        ActsAsTenant.with_tenant(cluster) do
          cluster.communities.each do |community|
            yield(community)
          end
        end
      end
    end
  end
end