# frozen_string_literal: true

module Billing
  class Template < ApplicationRecord
    acts_as_tenant :cluster

    belongs_to :community, inverse_of: :billing_templates
    has_many :template_member_types, class_name: "Billing::TemplateMemberType",
                                     inverse_of: :template, dependent: :destroy
    has_many :member_types, class_name: "People::MemberType", through: :template_member_types

    normalize_attributes :code, :description

    validates :code, presence: true
    validates :description, presence: true
    validates :amount, presence: true, numericality: {greater_than: 0}
  end
end
