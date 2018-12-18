# frozen_string_literal: true

# Users are the key to the whole thing!
class User < ApplicationRecord
  include PhotoDestroyable
  include Phoneable
  include Deactivatable

  ROLES = %i[super_admin cluster_admin admin biller photographer
             meals_coordinator wikiist work_coordinator].freeze
  ADMIN_ROLES = %i[super_admin cluster_admin admin].freeze
  CONTACT_TYPES = %i[email text phone].freeze
  NAME_ORDER = "LOWER(first_name), LOWER(last_name)"
  PASSWORD_MIN_ENTROPY = 16

  acts_as_tenant :cluster
  rolify

  attr_accessor :changing_password
  alias changing_password? changing_password

  # Currently, :database_authenticatable is only needed for tha password reset token features
  devise :omniauthable, :trackable, :recoverable, :database_authenticatable, :rememberable,
    omniauth_providers: [:google_oauth2]

  belongs_to :household, inverse_of: :users
  belongs_to :job_choosing_proxy, class_name: "User"
  has_many :job_choosing_proxiers, class_name: "User", foreign_key: :job_choosing_proxy_id,
                                   inverse_of: :job_choosing_proxy, dependent: :nullify
  has_many :up_guardianships, class_name: "People::Guardianship", foreign_key: :child_id,
                              dependent: :destroy, inverse_of: :child
  has_many :down_guardianships, class_name: "People::Guardianship", foreign_key: :guardian_id,
                                dependent: :destroy, inverse_of: :guardian
  has_many :guardians, through: :up_guardianships
  has_many :children, through: :down_guardianships
  has_many :meal_assignments, class_name: "Assignment", inverse_of: :user, dependent: :destroy
  has_many :work_assignments, class_name: "Work::Assignment", inverse_of: :user, dependent: :destroy
  has_many :work_shares, class_name: "Work::Share", inverse_of: :user, dependent: :destroy

  scope :active, -> { where(deactivated_at: nil) }
  scope :all_in_community_or_adult_in_cluster, lambda { |c|
    joins(household: :community)
      .where("communities.id = ? OR users.child = 'f'", c.id)
      .where("communities.cluster_id = ?", c.cluster_id)
  }
  scope :in_community, ->(id) { joins(:household).where("households.community_id = ?", id) }
  scope :by_name, -> { order(NAME_ORDER) }
  scope :by_unit, -> { joins(:household).order("households.unit_num, households.unit_suffix") }
  scope :by_active, -> { order("users.deactivated_at IS NOT NULL") }
  scope :sorted_by, ->(s) { s == "unit" ? by_unit : by_name }
  scope :by_name_adults_first, -> { order("CASE WHEN child = 't' THEN 1 ELSE 0 END, #{NAME_ORDER}") }
  scope :by_community_and_name, -> { includes(household: :community).order("communities.name").by_name }
  scope :active_or_assigned_to, lambda { |meal|
    t = arel_table
    where(t[:deactivated_at].eq(nil).or(t[:id].in(meal.assignments.map(&:user_id))))
  }
  scope :matching, ->(q) { where("(first_name || ' ' || last_name) ILIKE ?", "%#{q}%") }
  scope :can_be_guardian, -> { active.where(child: false) }
  scope :adults, -> { where(child: false) }
  scope :in_life_stage, ->(s) { s.to_sym == :any ? all : where(child: s.to_sym == :child) }

  ROLES.each do |role|
    # Using these scopes instead of with_role helps avoid invalid role mistakes.
    scope :"with_#{role}_role", -> { with_role(role) }
  end

  delegate :name, to: :household, prefix: true
  delegate :account_for, :credit_exceeded?, :other_cluster_communities, to: :household
  delegate :community_id, :community_name, :community_abbrv, :cluster,
    :unit_num, :unit_num_and_suffix, :vehicles, to: :household
  delegate :community, to: :household, allow_nil: true
  delegate :str, :str=, to: :birthdate_wrapper, prefix: :birthdate
  delegate :age, to: :birthdate_wrapper
  delegate :subdomain, to: :community

  normalize_attributes :email, :google_email, with: :email
  normalize_attributes :first_name, :last_name, :preferred_contact

  handle_phone_types :mobile, :home, :work # In order of general preference

  # Contact email does not have to be unique because some people share them (grrr!)
  validates :email, format: Devise.email_regexp, allow_blank: true
  validates :email, presence: true, if: :adult?
  validates :email, uniqueness: true, allow_nil: true
  validates :google_email, format: Devise.email_regexp, uniqueness: true,
                           unless: ->(u) { u.google_email.blank? }
  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :up_guardianships, presence: true, if: :child?
  validates :password, presence: true, if: :password_required?
  validates :password, password_strength: {use_dictionary: true, min_entropy: PASSWORD_MIN_ENTROPY},
                       if: :password_required_and_not_blank?

  validates :password, confirmation: true
  validate :household_present
  validate :at_least_one_phone, if: ->(u) { u.new_record? }
  validate { birthdate_wrapper.validate }

  has_attached_file :photo,
    styles: {thumb: "150x150#", medium: "300x300#"},
    default_url: "missing/users/:style.png"
  validates_attachment_content_type :photo, content_type: %w[image/jpg image/jpeg image/png image/gif]
  validates_attachment_size :photo, less_than: (Settings.photos.max_size_mb || 8).megabytes

  accepts_nested_attributes_for :household
  accepts_nested_attributes_for :up_guardianships, reject_if: :all_blank, allow_destroy: true

  # This is needed for remembering users across sessions because users don't always have passwords.
  before_create { self.remember_token ||= Devise.friendly_token }
  before_save { raise People::AdultWithGuardianError if adult? && guardians.present? }
  before_destroy { photo.destroy }
  after_update { Work::ShiftIndexUpdater.new(self).update }

  def self.from_omniauth(auth)
    find_by(google_email: auth.info[:email])
  end

  # Transient variable indicating whether the User's household is being edited by setting the ID.
  # The alternative is to edit it by using nested attributes. Used only in rendering the form.
  def household_by_id?
    @household_by_id
  end
  alias household_by_id household_by_id?

  # Setter for household_by_id?
  def household_by_id=(val)
    @household_by_id = val.is_a?(String) ? val == "true" : val
  end

  # Duck type.
  def users
    [self]
  end

  # Includes primary household plus any households affiliated by parentage.
  # For the case where children live in multiple households.
  # Alternatives for future refactors could be:
  # 1. children have multiple households
  # 2. children have household = nil and everything is determined by parentage. This may be better,
  #    would just have to remove the null constraint on household_id and think through implications.
  def all_households
    [household].concat(guardians.map(&:household)).uniq.shuffle
  end

  # Ensures provider and uid are set.
  def update_for_oauth!(auth)
    self.google_email = auth.info[:email]
    self.provider = "google_oauth2"
    self.uid = auth.uid
    save(validate: false)
  end

  def name
    "#{first_name} #{last_name}#{active? ? nil : ' (Inactive)'}"
  end

  def kind
    child? ? "child" : "adult"
  end

  def birthday
    birthdate_wrapper
  end

  def birthdate_wrapper
    @birthdate_wrapper ||= People::Birthdate.new(self)
  end

  def privacy_settings=(settings)
    settings = {} if settings.blank?
    settings.each { |k, v| settings[k] = ["1", "true", true].include?(v) }
    self[:privacy_settings] = settings
  end

  def any_assignments?
    meal_assignments.any?(&:persisted?) || work_assignments.any?(&:persisted?)
  end

  def any_job_choosing_proxies?
    self.class.where(job_choosing_proxy: self).any?
  end

  def any_work_shares?
    work_shares.any?(&:persisted?)
  end

  def any_guardianships?
    up_guardianships.any?(&:persisted?) || down_guardianships.any?(&:persisted?)
  end

  def any_created_meals?
    Meal.where(creator: self).any?
  end

  def any_reservations?
    Reservations::Reservation.where(reserver: self).any?
  end

  def any_sponsored_reservations?
    Reservations::Reservation.where(sponsor: self).any?
  end

  def any_wiki_contributions?
    Wiki::Page.where(creator: self).or(Wiki::Page.where(updator: self)).any? ||
      Wiki::PageVersion.where(updator: self).any?
  end

  def activate
    super
    household.user_activated
  end

  def deactivate
    super
    household.user_deactivated
  end

  def ensure_calendar_token!
    reset_calendar_token! if calendar_token.blank?
  end

  def reset_calendar_token!
    update_attribute(:calendar_token, generate_token)
  end

  # Exposing this as a public method.
  def reset_reset_password_token!
    set_reset_password_token
  end

  # All roles are currently global.
  # It might be tempting to scope e.g. meals_coordinator by community, but that would only make sense
  # if someone can e.g. be a meals_coordinator in multiple communities, which they can't.
  # Community scoping is already represented by the user's community or cluster affiliation.
  # The below methods are used to populate and receive params for the check boxes in the user form.
  ROLES.each do |role|
    define_method("role_#{role}") do
      has_role?(role)
    end

    define_method("role_#{role}=") do |bool|
      ["1", "true", true].include?(bool) ? add_role(role) : remove_role(role)
    end
  end

  # Efficiently does role lookups for global roles (those without associated resources) by caching
  # the user's roles. The has_role? method provided by Rolify does not do any caching which results in
  # a ton of unnecessary DB requests on some pages.
  def global_role?(role)
    global_roles[role].present?
  end

  def adult?
    !child?
  end

  # Devise method, instantly signs out user if returns false.
  def active_for_authentication?
    # We don't return false for adult inactive users because they
    # can still see some pages.
    adult?
  end

  def never_signed_in?
    sign_in_count.zero?
  end

  private

  def at_least_one_phone
    errors.add(:phone, "You must enter at least one phone number") if adult? && no_phones?
  end

  def generate_token
    loop do
      token = Devise.friendly_token
      break token unless User.find_by(calendar_token: token)
    end
  end

  def household_present
    return if household_id.present? || household.present? && !household.marked_for_destruction?
    errors.add(:household_id, :blank)
  end

  # Returns a hash of global roles (those with no associated resource) indexed by name.
  def global_roles
    @global_roles ||= roles.where(resource_id: nil).to_a.index_by(&:name).with_indifferent_access
  end

  def password_required?
    changing_password? || password.present? || password_confirmation.present?
  end

  def password_required_and_not_blank?
    password_required? && password.present?
  end
end
